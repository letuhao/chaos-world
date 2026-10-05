extends TestCase

## ADR 0102: the auction. The assertions are about escrow integrity (a lot cannot deliver a
## different roll than it froze a price for) and about bids being deterministic (no rng).

const COIN := &"curr_spirit_coin"
const GOOD := &"currency_spirit_stone"
const CHEAP := &"scroll_hemp"

## `Actor` is a `RefCounted`, so an actor built inside a helper is **freed the moment that
## helper returns** — the ledger stores ids, never references, so nothing keeps it alive.
## Every actor this suite creates is held here for exactly that reason, which is also what
## `test_loot_unique_routes.gd` does. Returning one from a helper produced a `no_actor`
## refusal three tests later and no visible cause.
var _held: Array[Actor] = []


func setup() -> void:
	# An auction lot is a WORLD fact: the bidder must see the seller's lot, or every bid
	# refuses `lot_not_open` (ADR 0101).
	MarketApi.set_store(MarketWorldLedger.new())
	_held.clear()


## The auction escrows a realized INSTANCE, so the fixture must produce one. A stackable
## added through `Inventory.add` lands in `_stacks`, and `remove_instance` only ever finds the
## `_instances` half — so the good is added as an instance directly, which is the same shape
## `loot` escrows.
func _shop_with_good(def_id: StringName) -> Actor:
	var actor := Actor.new()
	actor.id = &"auction_house"
	ItemsApi.attach(actor, 24)
	var def := Crafting.resolve(def_id)
	var instance := ItemInstance.new(def.id, &"lot_candidate")
	instance.def_ref = def
	instance.rarity = def.rarity
	instance.realm = def.realm
	ItemsApi.inventory(actor).add_instance(instance)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


## `Actor.tags` is typed `Array[StringName]`, so a plain `Array` cannot be assigned to it —
## and a REJECTED assignment returns from the function, so `_bidder` silently handed back null
## and every bid refused `no_actor` with no visible cause. Appended element-wise instead.
func _bidder(id: StringName, coins: int, tags: Array[StringName] = []) -> Actor:
	var actor := Actor.new()
	actor.id = id
	ItemsApi.attach(actor, 24)
	ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	for tag in tags:
		actor.tags.append(tag)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


func _list_good(shop: Actor) -> String:
	var instance_id := _first_instance_id(shop)
	var listed := MarketApi.list(shop, instance_id, 3)
	return String(listed.get("lot_id", ""))


func _first_instance_id(shop: Actor) -> StringName:
	for instance in ItemsApi.inventory(shop).instances():
		return instance.instance_id
	return &""


func test_listing_escrows_the_instance_out_of_the_sellers_inventory() -> void:
	# The escrow is the whole point: a lot that stayed in the seller's inventory could be
	# swapped for a different roll between listing and settlement.
	var shop := _shop_with_good(GOOD)
	assert_eq(ItemsApi.inventory(shop).instances().size(), 1, "the shop holds the good")
	var lot_id := _list_good(shop)
	assert_ne(lot_id, "", "the lot is created")
	assert_eq(ItemsApi.inventory(shop).instances().size(), 0, "and the instance is escrowed")


func test_a_lot_freezes_its_price_from_the_one_formula() -> void:
	var shop := _shop_with_good(GOOD)
	# `find_by_instance_id`, not `find_instance`: the latter matches `def_id` despite its
	# name, so it returned null here and the test died on a nil deref rather than on the
	# property it claims to assert.
	var instance := ItemsApi.inventory(shop).find_by_instance_id(_first_instance_id(shop))
	assert_eq(instance != null, true, "the escrow fixture is findable by instance id")
	if instance == null:
		return
	var listed := MarketApi.list(shop, instance.instance_id, 3)
	var expected := EconomyValuation.price_of(instance)
	assert_eq(bool(listed["ok"]), true, "the lot was listed: %s" % listed.get("reason", ""))
	assert_eq(int(listed["price"]), expected, "the lot price is the one formula's price")
	assert_eq(int(listed["opening"]) > expected, true, "and it opens above it")


func test_a_good_with_no_authored_worth_cannot_be_listed() -> void:
	# ADR 0094's floor makes an unauthored good CHEAP; an auction is not where a designer
	# invents a first price.
	var shop := _shop_with_good(CHEAP)
	var result := MarketApi.list(shop, _first_instance_id(shop), 3)
	assert_eq(bool(result["ok"]), false, "an unpriced good refuses to list")
	assert_eq(String(result["reason"]), MarketApi.LOT_UNPRICED, "and names the rule")


func test_a_seller_cannot_bid_on_their_own_lot() -> void:
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var result := MarketApi.bid(shop, StringName(lot_id), 999, 1)
	assert_eq(bool(result["ok"]), false, "the seller cannot bid")
	assert_eq(String(result["reason"]), MarketApi.SELLER_IS_BIDDER, "and names the rule")


func test_a_bid_must_meet_the_required_amount() -> void:
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var bidder := _bidder(&"rival", 500)
	var low := MarketApi.bid(bidder, StringName(lot_id), 1, 1)
	assert_eq(bool(low["ok"]), false, "a bid of one coin refuses")
	assert_eq(String(low["reason"]), MarketApi.BID_TOO_LOW, "and names the rule")


func test_a_bid_above_the_ceiling_is_refused() -> void:
	# The module already knows what the bidder could pay; recording a bid it knows is void
	# would have to be unwound at settlement.
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var bidder := _bidder(&"pauper", 10)
	var result := MarketApi.bid(bidder, StringName(lot_id), 500, 1)
	assert_eq(bool(result["ok"]), false, "a bid beyond the purse refuses")
	assert_eq(String(result["reason"]), MarketApi.BID_ABOVE_CEILING, "and names the rule")


func test_the_ceiling_is_the_purse_times_an_authored_appetite() -> void:
	# Deterministic by construction: same purse, same tag, same lot, same number. No rng.
	var collector := _bidder(&"rich_collector", 1000, [&"collector"] as Array[StringName])
	var thrifty := _bidder(&"rich_thrifty", 1000, [&"thrifty"] as Array[StringName])
	var collector_ceiling := AuctionState.bid_ceiling(1000, collector.tags)
	var thrifty_ceiling := AuctionState.bid_ceiling(1000, thrifty.tags)
	assert_eq(collector_ceiling > thrifty_ceiling, true, "a collector outbids a thrifty")
	assert_eq(
		AuctionState.bid_ceiling(1000, collector.tags),
		collector_ceiling,
		"the same purse and tag always give the same ceiling"
	)


func test_a_bid_must_strictly_exceed_so_ties_are_impossible() -> void:
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var opening := AuctionState.opening_bid({"price": 13})
	var exact := MarketApi.bid(_bidder(&"first", 500), StringName(lot_id), opening, 1)
	assert_eq(bool(exact["ok"]), true, "the opening bid is accepted")
	var same := MarketApi.bid(_bidder(&"second", 500), StringName(lot_id), opening, 2)
	assert_eq(bool(same["ok"]), false, "the same amount cannot win")


func test_settlement_pays_the_highest_bidder_and_delivers_the_good() -> void:
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var opening := AuctionState.opening_bid({"price": 13})
	var winner := _bidder(&"winner", 500)
	var placed := MarketApi.bid(winner, StringName(lot_id), opening, 1)
	assert_eq(bool(placed["ok"]), true, "the bid is placed")

	var paid := int(placed["amount"])
	var purse_before := EconomyApi.purse(winner)
	var house_before := EconomyApi.purse(shop)
	var settled := MarketApi.settle_lot(shop, _resolve_bidder([winner]), StringName(lot_id), 3)
	assert_eq(bool(settled["ok"]), true, "the lot settles: %s" % settled.get("reason", ""))
	assert_eq(String(settled["status"]), "sold", "and it sold")
	assert_eq(String(settled["winner"]), "winner", "to the high bidder")
	assert_eq(ItemsApi.inventory(winner).instances().size(), 1, "who received the good")
	# The house's purse is asserted too, because "the winner paid" and "the house received"
	# are the same fact from two sides and only the pair proves the coins actually MOVED
	# rather than being destroyed somewhere between.
	assert_eq(EconomyApi.purse(winner), purse_before - paid, "and paid their bid to the house")
	assert_eq(EconomyApi.purse(shop), house_before + paid, "which arrived at the house holding it")


func test_a_bidder_who_spent_their_money_loses_the_lot() -> void:
	# The purse is RE-READ at settlement, so a promise the bidder can no longer keep is
	# visible rather than a crash or a silent award.
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var opening := AuctionState.opening_bid({"price": 13})
	var winner := _bidder(&"winner", 500)
	MarketApi.bid(winner, StringName(lot_id), opening, 1)
	# Spend everything after bidding.
	ItemsApi.inventory(winner).remove(COIN, 500)
	var settled := MarketApi.settle_lot(shop, _resolve_bidder([winner]), StringName(lot_id), 3)
	assert_eq(String(settled["status"]), "unsold", "the lot goes unsold")
	assert_eq(ItemsApi.inventory(winner).instances().size(), 0, "and nobody receives it")


func test_settle_refuses_before_the_lot_is_due() -> void:
	var shop := _shop_with_good(GOOD)
	var lot_id := _list_good(shop)
	var result := MarketApi.settle_lot(shop, Callable(), StringName(lot_id), 1)
	assert_eq(bool(result["ok"]), false, "an early settle refuses")
	assert_eq(String(result["reason"]), MarketApi.LOT_NOT_DUE, "and names the rule")


func test_the_auction_reads_no_second_price_formula() -> void:
	# The structural pin (ADR 0084's shape). The auction may CALL the one formula and nothing
	# else. `base_worth_of` is the one legitimate exception and it is read for LISTABILITY,
	# not for a price: a good with no authored worth has no first price, and reading the raw
	# worth is the honest way to say so. What must never appear is a weight, a realm curve, or
	# a price assembled from parts.
	#
	# `auction_state.gd` is the pure arithmetic layer and is expected to name NO price at all —
	# it receives the lot's frozen price as data. `api.gd` is the only place that may price, and
	# it prices through `EconomyValuation.price_of`.
	var state_source := FileAccess.get_file_as_string("res://src/modules/market/auction_state.gd")
	for forbidden in ["RARITY_WEIGHT", "rarity_weight(", "RealmRate.", "unit_price(", "price_of("]:
		assert_eq(
			state_source.contains(forbidden), false, "auction_state.gd names no %s" % forbidden
		)

	var api_source := FileAccess.get_file_as_string("res://src/modules/market/api.gd")
	assert_eq(api_source.contains("RARITY_WEIGHT"), false, "api.gd names no rarity weight")
	assert_eq(api_source.contains("rarity_weight("), false, "api.gd calls no rarity weight")
	assert_eq(api_source.contains("RealmRate."), false, "api.gd names no realm curve")
	assert_eq(api_source.contains("unit_price("), false, "api.gd assembles no price from parts")
	# The frozen price comes from the ONE formula, at escrow.
	assert_eq(
		api_source.contains("EconomyValuation.price_of("),
		true,
		"api.gd prices through the one formula"
	)


func test_a_lot_round_trips_through_json() -> void:
	# ADR 0027: the escrowed roll must survive a save or the lot delivers something else.
	var shop := _shop_with_good(GOOD)
	_list_good(shop)
	var payload := MarketApi.state(shop)
	var restored: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	var lots: Dictionary = (restored as Dictionary)["lots"]
	assert_eq(lots.size(), 1, "and the lot survives")
	var lot: Dictionary = lots.values()[0]
	assert_eq(typeof(lot["instance_id"]), TYPE_STRING, "the instance id is a String")
	assert_eq(typeof(lot["signature"]), TYPE_STRING, "and so is the signature")


func _resolve_bidder(actors: Array) -> Callable:
	return func(_id: String) -> Actor: return actors[0] as Actor
