extends TestCase

## ADR 0094: the exchange primitive. The assertions here are about ATOMICITY and REFUSAL,
## because a trade that half-settles is worse than no trade at all.

## The numéraire, so a money test is a test about money and not about whatever an authored
## currency item happens to be worth this week. A realm-stamped currency def prices at its
## own rate, so it is a good rather than a unit of account (ADR 0094).
const COIN := &"curr_spirit_coin"

## An authored scroll that ships no `trade_value` at all, so it floors to 1 whatever its
## rarity — the honest "cheap good" here. Only 221 of the catalog's ~7900 items carry an
## authored worth, so a floor rather than a refusal is what keeps the rest tradeable.
const CHEAP := &"scroll_hemp"

## An authored currency item WITH a `trade_value`, so it carries a real price and is
## strictly dearer than a floored good. Used where a test needs two different price tiers
## rather than two equal ones.
const VALUED := &"currency_spirit_stone"

var _seller: Actor
var _buyer: Actor


func setup() -> void:
	_seller = _actor_with(COIN, 40)
	_buyer = _actor_with(COIN, 40)
	EconomyApi.attach(_seller)
	EconomyApi.attach(_buyer)


func _actor_with(def_id: StringName, quantity: int) -> Actor:
	var actor := Actor.new()
	actor.id = &"trader"
	ItemsApi.attach(actor)
	var def := Crafting.resolve(def_id)
	ItemsApi.inventory(actor).add(def, quantity)
	return actor


func _rows(def_id: StringName, quantity: int) -> Array:
	return [{"def_id": String(def_id), "quantity": quantity}]


func test_trade_moves_both_sides() -> void:
	# The seller offers a good, the buyer offers numeraire. Two DIFFERENT items, so the move
	# is observable in both directions rather than netting to zero.
	var goods := _actor_with(CHEAP, 4)
	EconomyApi.attach(goods)
	var result := EconomyApi.trade(goods, _buyer, _rows(CHEAP, 4), _rows(COIN, 4))
	assert_eq(bool(result["ok"]), true, "the exchange settles: %s" % result.get("reason", ""))
	assert_eq(int(result["offered"]), int(result["received"]), "the two legs are equal")
	assert_eq(ItemsApi.inventory(goods).count(CHEAP), 0, "the seller gave the goods")
	assert_eq(ItemsApi.inventory(_buyer).count(CHEAP), 4, "and the buyer received them")
	assert_eq(ItemsApi.inventory(goods).count(COIN), 4, "the seller received the money")
	assert_eq(ItemsApi.inventory(_buyer).count(COIN), 36, "and the buyer paid it")


func test_a_refused_trade_writes_nothing() -> void:
	# ADR 0044. The buyer holds nothing, so the want leg fails and the seller must be
	# untouched — the whole reason the plan is built before the first mutation.
	var result := EconomyApi.trade(_seller, _buyer, _rows(COIN, 10), _rows(CHEAP, 1))
	assert_eq(bool(result["ok"]), false, "an unpayable want refuses")
	assert_eq(
		String(result["reason"]),
		EconomyExchange.NOT_CARRIED,
		"the refusal names the rule, not free text"
	)
	assert_eq(ItemsApi.inventory(_seller).count(COIN), 40, "a refusal writes nothing")


func test_self_trade_is_refused() -> void:
	# Self-trade at a fixed price is a money printer — the only unbounded loop this design
	# could produce — so it is refused rather than clamped.
	var result := EconomyApi.trade(_seller, _seller, _rows(COIN, 10), _rows(COIN, 10))
	assert_eq(bool(result["ok"]), false, "self-trade refuses")
	assert_eq(String(result["reason"]), EconomyExchange.SAME_ACTOR, "self-trade is named")
	assert_eq(ItemsApi.inventory(_seller).count(COIN), 40, "and writes nothing")


func test_a_short_settlement_is_refused_in_either_direction() -> void:
	# The seller's side must not part with more than it takes. Reading that comparison the
	# other way round is the one bug an exchange can ship that lets a player take a 13-value
	# item for a single coin, and it reads as "the trade worked" in a test that only checks
	# that some trade worked. Pinned explicitly, in the direction that exploited it.
	var dear := _actor_with(VALUED, 1)
	EconomyApi.attach(dear)
	var price := EconomyApi.valuation(VALUED)
	assert_eq(int(price["price"]) > 1, true, "the valued good really is dearer than a coin")
	var result := EconomyApi.trade(_seller, dear, _rows(COIN, 1), _rows(VALUED, 1))
	assert_eq(bool(result["ok"]), false, "one coin cannot buy a valued good")
	assert_eq(
		String(result["reason"]), EconomyExchange.SETTLEMENT_SHORT, "it refuses on settlement"
	)
	assert_eq(ItemsApi.inventory(_seller).count(COIN), 40, "and writes nothing")
	assert_eq(ItemsApi.inventory(dear).count(VALUED), 1, "the seller keeps the good")


func test_a_full_receiving_inventory_refuses_rather_than_part_filling() -> void:
	# The BUYER receives the offer leg, so it is the buyer that must be full, and it must
	# actually HOLD the `want` leg — otherwise the refusal is `not_carried` and this test
	# would pass for the wrong reason. Both legs are priced at 1 so settlement passes and
	# the ONLY thing left to fail is room.
	var seller := _actor_with(CHEAP, 1)
	EconomyApi.attach(seller)
	var tiny := Actor.new()
	tiny.id = &"tiny"
	ItemsApi.attach(tiny, 1)
	EconomyApi.attach(tiny)
	ItemsApi.inventory(tiny).add(Crafting.resolve(COIN), 1)
	var result := EconomyApi.trade(seller, tiny, _rows(CHEAP, 1), _rows(COIN, 1))
	assert_eq(bool(result["ok"]), false, "a full inventory refuses")
	assert_eq(String(result["reason"]), EconomyExchange.NO_ROOM, "and names the room")
	assert_eq(ItemsApi.inventory(seller).count(CHEAP), 1, "the seller keeps the good")
	assert_eq(ItemsApi.inventory(tiny).count(COIN), 1, "the buyer keeps its money")


func test_a_one_sided_give_is_not_a_trade() -> void:
	# An offer of nothing is a gift, and a gift belongs to SocialApi.apply_cause
	# (ADR 0091's gift-spam guard) rather than to an exchange.
	var result := EconomyApi.trade(_seller, _buyer, [], _rows(COIN, 10))
	assert_eq(bool(result["ok"]), false, "a one-sided give refuses")
	assert_eq(
		String(result["reason"]), EconomyExchange.NO_SETTLEMENT, "a one-sided give is no settlement"
	)
	assert_eq(ItemsApi.inventory(_seller).count(COIN), 40, "and writes nothing")


func test_barter_conserves_every_row() -> void:
	# Barter is free: an exchange whose settlement is goods rather than money is the same
	# function with a different want. Asserted as CONSERVATION rather than as a chosen
	# price, because the point is that no leg had to be the numeraire.
	var left := _actor_with(CHEAP, 1)
	var right := _actor_with(VALUED, 1)
	EconomyApi.attach(left)
	EconomyApi.attach(right)
	var result := EconomyApi.trade(left, right, _rows(CHEAP, 1), _rows(VALUED, 1))
	if bool(result["ok"]):
		assert_eq(ItemsApi.inventory(left).count(CHEAP), 0, "the offer left the offerer")
		assert_eq(ItemsApi.inventory(right).count(VALUED), 0, "the want left the counterparty")
		assert_eq(ItemsApi.inventory(right).count(CHEAP), 1, "and the offer arrived")
		assert_eq(ItemsApi.inventory(left).count(VALUED), 1, "and the want arrived")
	else:
		# A refusal is equally correct when the two legs are unequal, and it must name the
		# settlement rather than anything about barter itself.
		assert_eq(
			String(result["reason"]),
			EconomyExchange.SETTLEMENT_SHORT,
			"unequal barter refuses on settlement"
		)


func test_history_is_recorded_and_bounded() -> void:
	# Each iteration swaps one coin each way, which leaves both sides unchanged — so the
	# seller never runs dry and the count is the count of SETTLED trades, not of attempts.
	for index in 40:
		EconomyApi.trade(_seller, _buyer, _rows(COIN, 1), _rows(COIN, 1))
	var summary := EconomyApi.summary(_seller)
	assert_eq(int(summary["trade_count"]), 40, "every settled trade is counted")
	assert_eq(int(summary["history_count"]), EconomyApi.MAX_HISTORY, "history is a bounded ring")
	assert_eq(bool(summary["history_truncated"]), true, "and it says when it truncated")
	assert_eq(ItemsApi.inventory(_seller).count(COIN), 40, "a same-item swap conserves both sides")


func test_summary_is_empty_without_an_actor() -> void:
	# The contract a panel tests instead of pixels.
	assert_eq(EconomyApi.summary(null), {}, "summary is {} with no actor")


func test_state_round_trips_through_json() -> void:
	# ADR 0027: module_data is String-keyed and JSON-round-tripped. An inner StringName
	# reaches the save untouched and breaks every round trip.
	EconomyApi.trade(_seller, _buyer, _rows(COIN, 1), _rows(COIN, 1))
	var payload := EconomyApi.state(_seller)
	var restored: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(typeof(restored), TYPE_DICTIONARY, "the ledger is JSON-safe")
	assert_eq(
		int((restored as Dictionary)["trade_count"]),
		int(payload["trade_count"]),
		"and it survives the round trip"
	)
