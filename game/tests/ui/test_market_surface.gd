extends TestCase

## The shop and auction surfaces, end to end: a player stands at a market row, buys
## something off a stall's shelf, lists a lot and bids on one — and the goods and the
## coins are where the ledger says afterwards.
##
## ## What this suite is FOR
##
## Two read models shipped and **nothing in the shipped program ever asked either one
## for**. `ShopCounter.at_location` publishes `{location_id, shops, shop_count}` where
## every row is a priced shelf plus a `can_buy`, and calls itself "the door a caller
## actually walks through"; `AuctionReadModel.lots` publishes `required_bid`,
## `high_bid` and `high_bid_amount` for every lot in the world. `MarketApi.buy`,
## `sell`, `list` and `bid` were all green in every suite. So a shop was authored
## content a catalog could read and a player could never meet, and an auction was a
## frozen price, an escrow and a settlement walk nobody could watch.
##
## Every case here drives the screen the way a player does and asserts the OUTCOME in
## the bag and the purse. A screen that rendered a row and moved nothing would pass a
## "the button is enabled" assertion, and a screen that conjured items would pass
## nothing else — so both sides are read off the same world the module writes.
##
## ## Both screens are PURE CONSUMERS of `app/`, and each says WHY
##
## `market` IS declared in `rules.UI_MODULES`, so a screen may name `MarketApi` by
## bare name — which is how `ForageScreen` calls `HoldingsApi.claim`. What it may NOT
## do is name `ShopCounter` (an `app/` type, and `app` is the only entry in
## `rules.PRIVATE_UNITS`) nor `AuctionBids`. So:
##
##  - the market screen takes its priced read model AND its verbs as Callables,
##    because `MarketApi.buy(shop_actor, player, rows)` needs a merchant `Actor` that
##    only `ShopCounter.counter` mints;
##  - the auction screen calls `MarketApi.list` BY NAME — every argument is the bound
##    actor and two plain ids — and takes only the BID as a Callable.
##
## The split is the claim, and
## `test_the_auction_screen_reaches_the_verbs_by_the_only_two_roads_there_are` asserts it
## from the shipped source rather than restating it here.
##
## ## Nothing leaks
##
## `MarketApi.set_store` and `ShopCounter`'s counter cache are PROCESS-WIDE and the
## runner shares ONE process across every suite, calling `teardown` after EVERY test.
## A shop counter left installed holds a live `Actor` with a realized `Inventory`
## alive until the engine shuts down, which ObjectDB then reports as leaked instances
## at exit with every assertion green. So the store and the counters are released
## per-test, not per-suite.

const MARKET_SCENE := preload("res://src/ui/screens/market_screen.tscn")
const AUCTION_SCENE := preload("res://src/ui/screens/auction_screen.tscn")
const SHOP_ROW_SCENE := preload("res://src/ui/panels/market_row.tscn")
const LOT_ROW_SCENE := preload("res://src/ui/panels/auction_lot_row.tscn")

const MARKET_SCRIPT_PATH := "res://src/ui/screens/market_screen.gd"
const AUCTION_SCRIPT_PATH := "res://src/ui/screens/auction_screen.gd"
const SHOP_ROW_SCRIPT_PATH := "res://src/ui/panels/market_row.gd"
const LOT_ROW_SCRIPT_PATH := "res://src/ui/panels/auction_lot_row.gd"
const ROOT_SCRIPT_PATH := "res://src/app/item_workbench_app.gd"

const MARKET_ROUTE := &"market"
const AUCTION_ROUTE := &"auction"

## The numéraire. A literal, because `EconomyValuation.numeraire_id()` is a FUNCTION and
## a `const` may not call one — and `test_economy_content.gd` already pins that this id
## prices at exactly 1 and is stackable, so a drift in the module fails there rather
## than here. `MarketScreen` reads its purse through the facade rather than through this
## literal, which is what makes the two agreeing a fact instead of a coincidence.
const COIN := &"curr_spirit_coin"
## An authored reagent the reagent trader both stocks and buys, read off the shelf the
## facade publishes — so a retune of `foundation_reagent_trader`'s stock cannot leave
## this suite buying a good the build no longer ships.
const SHOP_ID := &"foundation_reagent_trader"
## The reagent row the authored `.tres` files that stall's `location_id`.
const SHOP_LOCATION := &"foundation_reagent_row"
## A good with an authored worth, so `MarketApi.list` will escrow rather than refuse
## `lot_unpriced`. `currency_spirit_stone` is the same fixture the auction suites use.
const AUCTION_GOOD := &"currency_spirit_stone"
## Enough purse that `AuctionState.bid_ceiling` at the default 30% appetite clears the
## lot's opening. Read from the module's own percent table rather than guessed.
const BIDDER_PURSE := 4000

## Every actor this suite creates. `Actor` is a `RefCounted`, so one built inside a
## helper is freed the moment that helper returns — the ledger stores ids, never
## references, so nothing keeps it alive. Holding them is the same reason
## `tests/modules/market/test_market_auction.gd` does it.
var _held: Array[Actor] = []
var _shop: Actor = null


func setup() -> void:
	# A lot, a floor and a purse are WORLD facts (ADR 0101), so a fresh store is not
	# belt-and-braces here: it is what makes a bidder able to see the seller's lot at
	# all. Without one a bid refuses `lot_not_open` against another suite's ledger.
	MarketApi.set_store(MarketWorldLedger.new())
	ShopCounter.reset()
	ShopCatalog.instance().reset()
	_held.clear()


func teardown() -> void:
	# Process-wide, and the runner calls this after EVERY test. A counter is a live
	# Actor holding a realized Inventory, so leaving one installed leaks that graph
	# for the life of the process and the next suite inherits its stock.
	ShopCounter.reset()
	ShopCatalog.instance().reset()
	MarketApi.set_store(null)
	_held.clear()


# --- fixtures ----------------------------------------------------------------


## A hero with a bag, an economy ledger and a market ledger, which is everything a
## buy needs and everything a list escrows. `Actor` is held, never returned, per the
## class note.
func _hero(id: StringName, coins: int) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, 24)
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	actor.set_module_data("world_spawn_state", {})
	if coins > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	_held.append(actor)
	return actor


## A REALIZED instance of `def_id` in the hero's bag, which is the only thing
## `MarketApi.list` will escrow: `Inventory.remove_instance` reaches the `_instances`
## half, and a stackable added through `add` lives in `_stacks`.
func _instance(actor: Actor, def_id: StringName, instance_id: StringName) -> String:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "setup: '%s' resolves to an ItemDef" % def_id)
	if def == null:
		return ""
	var instance := ItemInstance.new(def.id, instance_id)
	instance.def_ref = def
	instance.rarity = def.rarity
	instance.realm = def.realm
	# A realized price must come from AUTHORED worth: ADR 0094 refuses an instance whose
	# `rolled` carries a `trade_value`, and `list` answers `no_settlement` for one.
	instance.rolled = []
	ItemsApi.inventory(actor).add_instance(instance)
	return String(instance.instance_id)


## The market screen bound to `hero` and pointed at the reagent row, with the seams
## wired exactly as `ItemWorkbenchApp._bind_route_screen`'s `ROUTE_MARKET` arm wires
## them: the bare static function for the read model, and the root's own instance
## methods for the two verbs (which need a counter this program resolves).
func _market(hero: Actor) -> MarketScreen:
	var screen := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	screen.setup(hero)
	screen.at_location(SHOP_LOCATION)
	screen.bind_market(
		Callable(ShopCounter, "at_location"),
		func(shop_id: StringName, player: Actor, rows: Array) -> Dictionary:
			var counter := ShopCounter.counter(shop_id)
			if counter == null:
				return {"ok": false, "reason": ShopCounter.UNKNOWN_SHOP, "coins": 0}
			return MarketApi.buy(counter, player, rows),
		func(shop_id: StringName, player: Actor, rows: Array) -> Dictionary:
			var counter := ShopCounter.counter(shop_id)
			if counter == null:
				return {"ok": false, "reason": ShopCounter.UNKNOWN_SHOP, "coins": 0}
			return MarketApi.sell(ShopCatalog.instance().definition(shop_id), counter, player, rows)
	)
	return screen


## The auction screen bound to `hero`, with the bid seam wired exactly as the
## `ROUTE_AUCTION` arm wires it: the bare static function, not a lambda.
func _auction(hero: Actor) -> AuctionScreen:
	var screen := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	screen.setup(hero)
	screen.bind_auction(Callable(AuctionBids, "bid"))
	return screen


## Every lot in the world as the READ MODEL sees them — through `MarketApi.summary`,
## which goes via the shared world store, and never through `MarketApi.state`, whose
## actor mirror goes stale.
func _lots() -> Array:
	var reader := _hero(&"a_lot_reader", 0)
	return MarketApi.summary(reader).get("lots", []) as Array


## The one lot in the world, or `{}` so a broken fixture turns the NEXT assertion red
## with a message rather than aborting this one halfway through.
func _lot() -> Dictionary:
	var rows := _lots()
	assert_eq(rows.size(), 1, "the fixture listed exactly one lot")
	return (rows[0] as Dictionary) if rows.size() == 1 else {}


## The reagent row for the stall this suite trades at, read off the facade rather than
## restated, so the case follows content rather than pinning a literal.
func _shelf_row(shop_id: StringName, def_id: StringName) -> Dictionary:
	for row in ShopCounter.at_location(SHOP_LOCATION, _shop).get("shops", []) as Array:
		if String((row as Dictionary).get("shop_id", "")) != String(shop_id):
			continue
		for line in (row as Dictionary).get("shelf", []) as Array:
			if String((line as Dictionary).get("def_id", "")) == String(def_id):
				return line as Dictionary
	return {}


# --- the market, end to end --------------------------------------------------


## THE claim of the market half. A player opens the page, the stall's shelf RENDERS,
## and buying moves both goods and coins.
##
## Both halves are asserted because either alone is satisfiable by a lie: a screen
## that showed a row and wrote nothing would pass a "the button is enabled"
## assertion, and a screen that conjured items would pass nothing else. The goods are
## read off the BAG and the coins out of the module's own purse, so the two sides
## cannot be satisfied by the same fiction.
func test_a_player_buys_from_a_stalls_shelf_and_the_goods_and_coins_both_move() -> void:
	_shop = _hero(&"shopper", 4000)
	var screen := _market(_shop)

	# Beat one: the SHELF renders. Read off the row pool, not the facade, so what the
	# player can see and what the verb will act on cannot be two different worlds.
	var listed := screen.summary()["shop_ids"] as Array
	assert_ne(listed.is_empty(), true, "the authored stall has a row on the page")
	assert_eq(listed.has(String(SHOP_ID)), true, "and it is the stall the content authors here")
	var row := _row_for(screen, String(SHOP_ID))
	assert_ne(row, {}, "the picked stall fills a row")
	var shelf := _shelf_row(SHOP_ID, &"alchemy_mist_herb")
	assert_ne(shelf, {}, "setup: the shelf prices a herb the hero will buy")
	# The panel owns the format, so the row's OWN line carries the figures — which is
	# the half a number-only assertion cannot see.
	assert_ne(
		String(row["shelf_line"]).find(str(int(shelf["coins"]))),
		-1,
		"the rendered shelf line carries the charge the verb will settle"
	)
	assert_eq(bool(row["can_buy"]), true, "a 4000-coin purse reaches the reagent row")

	# Beat two: the BUY runs. 4000 coins, one line off the shelf.
	# The stall the verbs act on is the PICK, never the first row: `act_buy` refuses
	# `no_shop_picked` on an empty pick rather than silently acting on whichever row
	# happens to be first, so a test that never picked was measuring a refusal and then
	# reading the refusal's dictionary as a purchase.
	assert_eq(screen.select_shop(String(SHOP_ID)), true, "the stall is selectable")
	var counter := ShopCounter.counter(SHOP_ID)
	assert_ne(counter, null, "setup: the stall is realized, so it has a bag to sell from")
	var counter_before := ItemsApi.inventory(counter).count(StringName(shelf["def_id"]))
	assert_ne(counter_before, 0, "setup: the counter really holds the good this test buys away")
	var before := EconomyApi.purse(_shop)
	var bought := screen.act_buy(String(shelf["def_id"]))
	assert_eq(bool(bought["ok"]), true, "the purchase is accepted: %s" % bought["reason"])
	assert_eq(bought.has("coins"), true, "and the verdict carries a settlement figure")
	assert_eq(int(bought["coins"]), int(shelf["coins"]), "and it charges the shelf's own price")
	assert_eq(
		ItemsApi.has_item(_shop, StringName(shelf["def_id"]), int(shelf["quantity"])),
		true,
		"and the hero really holds %d of '%s'" % [int(shelf["quantity"]), shelf["def_id"]]
	)
	assert_eq(
		EconomyApi.purse(_shop),
		before - int(shelf["coins"]),
		"so the coins left the purse for exactly what the shelf charged"
	)
	# The counter and the world cannot both still have the goods, or the item exists
	# twice.
	#
	## ## What is asserted is the COUNTER's bag, and why neither other figure would do
	#
	# `ShopDef.stock` is the AUTHORED BASELINE the counter is realized from, and nothing
	# decrements it — so a stall whose stock entry is still 10 after a purchase has
	# answered nothing, and asserting it went to zero was measuring a `.tres` constant
	# rather than a transfer. The counter's summary is not the right place either:
	# `MarketApi.buy` escrows through `Inventory.remove_instance`, which removes a
	# realized INSTANCE, and a stackable the def authors is bought back as a fresh
	# realization in a NEW slot — so the summary still lists a `quantity` for a def
	# whose authored stack is gone.
	#
	# The fact ADR 0100 makes is "the goods leave the merchant", and the one reader of it
	# is `Inventory.count` on the COUNTER's own bag: it sums every slot carrying that
	# def id however the bag files it. Read BEFORE the trade and again after it, and the
	# difference is the claim. `ShopCounter.summary`'s `stock` is deliberately NOT the
	# figure: it lists one row PER STACK, and a realized instance bought back into a
	# fresh slot is a second row rather than a smaller first one.
	var bought_quantity := int(shelf["quantity"])
	assert_eq(
		ItemsApi.inventory(counter).count(StringName(shelf["def_id"])),
		counter_before - bought_quantity,
		"and the merchant holds exactly that much less: the goods LEAVE it (ADR 0100)"
	)
	screen.free()


## A sell is the other direction of the same counter, and it is refused by the SHOP's
## authored `buys` list rather than by anything the screen decided — which is what
## makes a black market a content choice rather than a price modifier.
func test_selling_to_a_stall_moves_the_goods_the_other_way() -> void:
	_shop = _hero(&"seller", 200)
	var herb := _instance(_shop, &"alchemy_mist_herb", &"herb_for_sale")
	assert_ne(herb, "", "setup: the hero holds a realized herb instance")
	var screen := _market(_shop)
	assert_eq(screen.select_shop(String(SHOP_ID)), true, "the stall is selectable")

	var before := EconomyApi.purse(_shop)
	var sold := screen.act_sell("alchemy_mist_herb", 1)
	assert_eq(
		bool(sold["ok"]), true, "the stall authors this herb on its buys list: %s" % sold["reason"]
	)
	assert_eq(
		ItemsApi.inventory(_shop).count(&"alchemy_mist_herb"), 0, "and the hero's copy is gone"
	)
	assert_eq(
		bool(EconomyApi.purse(_shop) > before),
		true,
		"and the stall paid more than nothing, which is the spread's whole point"
	)
	screen.free()


## The refusal is RENDERED rather than the control greyed out, and it is named. A
## player told nothing may still be told why nothing happened, and a panel that
## reworded the module's own constant would be describing a rule nobody wrote.
func test_a_shop_that_buys_nothing_refuses_the_sell_by_its_own_name() -> void:
	_shop = _hero(&"black_market", 0)
	var listed := ShopCatalog.instance().at_location(SHOP_LOCATION)
	assert_ne(listed.is_empty(), true, "setup: a stall trades at the reagent row")
	var black := _black_market_def()
	ShopCatalog.instance().install([black])
	var def := ShopCatalog.instance().definition(black.shop_id)
	assert_eq(def.buys_def(&"alchemy_mist_herb"), false, "setup: it buys nothing at all")
	var screen := _market(_shop)
	assert_eq(
		screen.select_shop(String(black.shop_id)),
		true,
		"an authored stall is selectable even when it buys nothing"
	)
	var sold := screen.act_sell("alchemy_mist_herb", 1)
	assert_eq(bool(sold["ok"]), false, "nothing to sell into, so there is nothing to hand over")
	assert_eq(
		bool(screen.summary()["enabled"]["sell"]),
		true,
		"and the control stays LIVE: the refusal is the module's, not the screen's guess"
	)
	screen.free()


## The refusal a player gets when the page has no seam is a NAMED one, and it is
## distinct from every module refusal: the shelf was priced and there is nowhere to
## send the trade. An unbound screen that quietly did nothing is the failure this
## whole assertion family exists for.
func test_an_unbound_market_screen_refuses_no_market_seam_by_name() -> void:
	_shop = _hero(&"unbound", 4000)
	var screen := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	screen.setup(_shop)
	screen.at_location(SHOP_LOCATION)
	screen.bind_market(Callable(), Callable(), Callable())
	assert_eq(bool(screen.summary()["market_wired"]), false, "the screen knows it cannot trade")
	screen.select_shop(String(SHOP_ID))
	var bought := screen.act_buy()
	assert_eq(bool(bought["ok"]), false, "so a buy cannot run")
	assert_eq(
		String(bought["reason"]),
		MarketScreen.NO_MARKET_SEAM,
		"and the refusal names the missing seam rather than reporting a purchase nobody ran"
	)
	assert_eq(
		ItemsApi.inventory(_shop).snapshot().stacks().is_empty(),
		false,
		"and the hero's bag holds only what they came in with: nothing was conjured"
	)
	screen.free()


## No location means no stalls, which is a different sentence from "the room is
## empty". The refusal is by name so one renderer covers both.
func test_a_market_with_no_location_names_no_shops_rather_than_listing_everyone() -> void:
	_shop = _hero(&"nowhere", 4000)
	var screen := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	screen.setup(_shop)
	screen.bind_market(Callable(ShopCounter, "at_location"), Callable(), Callable())
	screen.bind_market(
		Callable(ShopCounter, "at_location"),
		func(_a: StringName, _p: Actor, _r: Array) -> Dictionary: return {},
		func(_a: StringName, _p: Actor, _r: Array) -> Dictionary: return {}
	)
	# Explicitly typed, not `:=`: `Dictionary` subscript is a `Variant`, and inferring
	# from one is a parse error in this repo.
	var located: Variant = screen.summary()["located"]
	assert_eq(
		bool(located),
		false,
		(
			"nothing was named, so nothing is located; the key is a BOOLEAN, so `String()` "
			+ "on it would read 'false' as a location id"
		)
	)
	var bought := screen.act_buy()
	assert_eq(String(bought["reason"]), MarketScreen.NO_LOCATION, "and the refusal says so")
	screen.free()


## Every authored stall is a row. A stall that silently vanished would read as content
## the build does not have, which is the dead-content failure ADR 0063 shipped once.
func test_every_authored_stall_at_a_row_is_listed_rather_than_truncated() -> void:
	_shop = _hero(&"browser", 4000)
	# Read the locations off the CONTENT tree rather than typing one in, so a retune of
	# a `.tres` cannot leave this suite probing a row the build no longer ships.
	var locations: Array[StringName] = []
	for id in ShopCatalog.instance().shop_ids():
		var def := ShopCatalog.instance().definition(id)
		if def != null and def.location_id != &"":
			locations.append(def.location_id)
	assert_ne(locations.is_empty(), true, "the catalog authors stalls that trade somewhere")
	for location in locations:
		var screen := _market(_shop)
		screen.at_location(location)
		var authored := ShopCounter.at_location(location, _shop).get("shops", []) as Array
		var listed := screen.summary()["shop_ids"] as Array
		assert_eq(
			listed.size(),
			authored.size(),
			"every stall at '%s' is a row, not the pool's size" % location
		)
		for row in authored:
			assert_eq(
				listed.has(String((row as Dictionary).get("shop_id", ""))),
				true,
				"%s has a row at '%s'" % [(row as Dictionary).get("shop_id", ""), location]
			)
		screen.free()


## The purse the screen publishes is the module's own, read through `MarketApi.summary`
## by bare name — the one facade call `ui/` may make here without a seam. Asserted
## against the module directly so a screen that re-derived a purse would go red.
##
## ## The message is formatted, never spliced
##
## A `Variant` reaches this as whatever it is, so `"%s" % reported` is the only way to
## name a whole dictionary here: the earlier `"...: %s" % offenders` form binds ONE
## array element to the single `%s` and Godot refuses the rest of the format string,
## which is a runtime error rather than a red assertion.
func test_the_screen_reports_the_purse_the_module_reads() -> void:
	_shop = _hero(&"counting", 777)
	var screen := _market(_shop)
	var reported := screen.summary()
	assert_eq(
		int(reported["purse"]),
		EconomyApi.purse(_shop),
		"the published purse is the module's, not one the screen composed"
	)
	var offenders := _non_primitives(reported, "")
	var offenders_text := str(offenders)
	assert_eq(
		offenders.is_empty(),
		true,
		"the published purse came with primitives only: %s" % offenders_text
	)
	screen.free()


# --- the auction, end to end -------------------------------------------------


## THE claim of the auction half. A player lists a lot, and the ESCROW is real — the
## good leaves their bag — and the lot shows up on the page with the frozen price and
## the required bid.
func test_a_player_lists_a_lot_and_it_appears_with_its_frozen_price_and_opening() -> void:
	var seller := _hero(&"lot_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"listed_spirit_stone")
	assert_ne(instance_id, "", "setup: the seller holds a realized instance to escrow")
	var screen := _auction(seller)
	assert_eq(
		screen.listable_instance_ids().has(instance_id),
		true,
		"the hero's own instance is listable, so the action is live"
	)
	assert_eq(
		ItemsApi.inventory(seller).count(AUCTION_GOOD),
		1,
		"and the good is in the bag before the escrow"
	)

	var listed := screen.act_list(instance_id, 3)
	assert_eq(bool(listed["ok"]), true, "the lot opens: %s" % listed["reason"])
	var lot_id := String(listed["lot_id"])
	assert_ne(lot_id, "", "and it has an id a row can be named by")
	assert_eq(
		ItemsApi.inventory(seller).instances().is_empty(),
		true,
		"the instance is ESCROWED out of the seller's bag, not copied (ADR 0102)"
	)

	var row := _lot_row_for(screen, lot_id)
	assert_ne(row, {}, "the lot is a row on the page")
	assert_eq(String(row["status"]), AuctionScreen.STATUS_OPEN, "and it is open")
	assert_eq(
		int(row["required_bid"]),
		int(listed["opening"]),
		"the row publishes the opening the module froze, so a bidder reads the real number"
	)
	assert_eq(bool(row["mine"]), true, "and the row knows the hero is its seller")
	assert_eq(
		bool(row["can_bid"]),
		false,
		"so the bid control is DEAD on your own lot, rather than live and refusing"
	)
	screen.free()


## THE claim of the second beat: a player lists nothing and bids on somebody's, and
## **the high bid is shown afterwards**. Asserted against the LEDGER and the row, so
## a screen that rendered a stale row cannot pass.
func test_a_player_bids_and_the_high_bid_is_shown_on_the_lot() -> void:
	var seller := _hero(&"rival_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"contested_stone")
	var listed := MarketApi.list(seller, StringName(instance_id), 3)
	assert_eq(bool(listed["ok"]), true, "setup: the rival listed a lot")
	var lot_id := String(listed["lot_id"])

	var bidder := _hero(&"hero", BIDDER_PURSE)
	var screen := _auction(bidder)
	var before := _lot_row_for(screen, lot_id)
	assert_ne(before, {}, "the rival's lot is on the page")
	assert_eq(String(before["high_bid"]), "", "nobody is bidding on it yet, and the row says so")
	assert_eq(bool(before["can_bid"]), true, "and this purse reaches the opening")

	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), true, "the bid is placed: %s" % bid["reason"])
	# ## The amount is `maxi(required, ceiling)`, and this purse's ceiling is ABOVE the
	# required bid
	#
	# `AuctionBids.bid` is the one place the bid figure exists: it derives
	# `AuctionState.bid_ceiling(purse, tags)` and takes `maxi(required, ceiling)`, so a
	# bidder with appetite to spare commits MORE than the minimum. A deep purse
	# therefore does NOT bid the required amount, and asserting it did was asserting the
	# auction's arithmetic wrong rather than the surface. What is asserted is the
	# ARITHMETIC, from both ends: the seam published the ceiling and the required bid,
	# and the ledger's standing is the maximum of the two.
	assert_eq(
		int(bid["amount"]),
		maxi(int(before["required_bid"]), int(bid["ceiling"])),
		"the standing is the auction's own maxi(required, ceiling)"
	)
	assert_eq(
		int(bid["required"]),
		int(before["required_bid"]),
		"and the required bid is the row's own figure"
	)
	assert_eq(
		int(bid["amount"]) >= int(before["required_bid"]),
		true,
		"a first bid on an unbid lot is never below the required amount"
	)
	# Read the lot back out of the LEDGER, not out of the return value: the return is
	# the seam's answer about itself, and the ledger is what the world now holds.
	var after := _lot_row_for(screen, lot_id)
	assert_eq(
		String(after["high_bid"]), String(bidder.id), "the ledger names this hero the high bidder"
	)
	assert_eq(int(after["high_bid_amount"]), int(bid["amount"]), "at the amount it committed")
	assert_eq(int(after["bid_count"]), 1, "and the lot records exactly one bid")
	# The row's OWN sentence, because "the high bid is shown" is a rendering claim and
	# a number-only assertion cannot see it.
	assert_ne(
		String(after["high_line"]).find(String(bidder.id)),
		-1,
		"the row PRINTS the high bidder's name, so a player can read who is winning"
	)
	assert_ne(
		String(after["high_line"]).find(str(int(bid["amount"]))), -1, "and the amount they stand at"
	)
	screen.free()


## A lot a hero cannot afford is a row that says so and a bid that is DEAD, which is
## the "looks alive and is dead" shape the UI standard exists to prevent. Asserted
## from the control state AND the refusal.
func test_a_lot_beyond_the_purse_is_not_bid_on_and_the_refusal_names_the_rule() -> void:
	var seller := _hero(&"rich_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"dear_stone")
	var listed := MarketApi.list(seller, StringName(instance_id), 3)
	assert_eq(bool(listed["ok"]), true, "setup: the lot is on the board")
	var lot_id := String(listed["lot_id"])
	var required := int(listed["opening"])

	var pauper := _hero(&"pauper", 1)
	var screen := _auction(pauper)
	var row := _lot_row_for(screen, lot_id)
	assert_ne(row, {}, "the lot is still visible to a hero who cannot afford it")
	assert_eq(bool(row["can_bid"]), false, "but the row reports it as beyond the purse")
	screen.select_lot(lot_id)
	assert_eq(
		bool(screen.summary()["enabled"]["bid"]),
		false,
		"so the bid control is DEAD, rather than live and refusing"
	)
	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), false, "and pressing anyway cannot place a bid")
	assert_eq(
		String(bid["reason"]),
		AuctionBids.CEILING_BELOW_REQUIRED,
		"the refusal is the AUCTION'S own id, passed through by name"
	)
	assert_eq(
		String(_lot()["high_bid"]), "", "and no bidder was recorded: a refusal writes nothing"
	)
	assert_eq(int(_lot()["high_bid_amount"]), 0, "at no amount either")
	screen.free()


## The seller cannot bid on their own lot, and the row says so before the press. The
## module's refusal is passed through rather than pre-judged, because
## `already_high` and `seller_is_bidder` are different sentences a panel reads.
func test_a_seller_cannot_bid_on_their_own_lot_and_the_refusal_names_the_rule() -> void:
	var seller := _hero(&"self_bidder", 9000)
	var instance_id := _instance(seller, AUCTION_GOOD, &"own_stone")
	var listed := screen_free_list(seller, instance_id)
	assert_eq(bool(listed["ok"]), true, "setup: the hero listed it")
	var lot_id := String(listed["lot_id"])

	var screen := _auction(seller)
	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), false, "a seller is not a bidder")
	assert_eq(
		String(bid["reason"]), MarketApi.SELLER_IS_BIDDER, "and the refusal is the module's id"
	)
	screen.free()


## A bid with no seam is refused BY NAME, distinct from every module refusal: the
## amount was computed and there was nowhere to send it. This is the assertion that
## keeps the `ROUTE_AUCTION` arm from being deleted silently.
func test_an_unbound_auction_screen_refuses_no_auction_seam_by_name() -> void:
	var seller := _hero(&"unbound_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"unbound_stone")
	var listed := screen_free_list(seller, instance_id)
	assert_eq(bool(listed["ok"]), true, "setup: a lot exists to bid on")

	var bidder := _hero(&"unbound_bidder", BIDDER_PURSE)
	var screen := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	screen.setup(bidder)
	screen.bind_auction(Callable())
	assert_eq(bool(screen.summary()["auction_wired"]), false, "the screen knows it cannot bid")
	var bid := screen.act_bid(String(listed["lot_id"]))
	assert_eq(bool(bid["ok"]), false, "so a bid cannot run")
	assert_eq(
		String(bid["reason"]),
		AuctionScreen.NO_AUCTION_SEAM,
		"and the refusal names the missing seam rather than reporting a bid nobody placed"
	)
	assert_eq(String(_lot()["high_bid"]), "", "and no bidder was recorded")
	screen.free()


## Every lot in the world is a row, and a lot that silently vanished would read as
## content the build does not have. Stated against the facade's own count rather than
## a literal, so a content wave cannot leave this suite pinned to a number.
func test_every_lot_in_the_world_is_a_row_rather_than_truncated() -> void:
	var seller := _hero(&"lister", 0)
	for index in range(3):
		var instance_id := _instance(seller, AUCTION_GOOD, StringName("stone_%d" % index))
		assert_eq(
			bool(MarketApi.list(seller, StringName(instance_id), 3)["ok"]),
			true,
			"setup: lot %d is on the board" % index
		)
	var bidder := _hero(&"watcher", BIDDER_PURSE)
	var screen := _auction(bidder)
	assert_eq(
		(screen.summary()["lot_ids"] as Array).size(),
		_lots().size(),
		"one row per lot in the world, not the pool's size"
	)
	for row in _lots():
		assert_eq(
			(screen.summary()["lot_ids"] as Array).has(String((row as Dictionary)["lot_id"])),
			true,
			"%s has a row" % (row as Dictionary)["lot_id"]
		)
	screen.free()


## A good with no authored worth cannot be escrowed, and the refusal is the module's
## own id rather than a screen sentence. ADR 0094's floor makes an unauthored good
## CHEAP; an auction is not where a designer invents a first price.
func test_a_good_with_no_authored_worth_cannot_be_listed_and_says_so() -> void:
	var hero := _hero(&"listing_a_pebble", 0)
	var instance_id := _instance(hero, &"scroll_hemp", &"pebble")
	assert_ne(instance_id, "", "setup: the hero holds an unauthored good as an instance")
	var screen := _auction(hero)
	var listed := screen.act_list(instance_id, 3)
	assert_eq(bool(listed["ok"]), false, "an unpriced good refuses to list")
	assert_eq(
		String(listed["reason"]), MarketApi.LOT_UNPRICED, "and the refusal names the module's rule"
	)
	assert_eq(
		ItemsApi.inventory(hero).instances().size(),
		1,
		"and the good is untouched: a refused list escrows nothing"
	)
	screen.free()


# --- the screen contract -----------------------------------------------------


## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state
## unreadable rather than merely empty. Both screens, because both are routed.
func test_both_screen_summaries_are_empty_without_an_actor() -> void:
	var market := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	assert_eq(market.summary(), {}, "the market reports nothing, not keys, with no hero")
	market.free()
	var auction := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	assert_eq(auction.summary(), {}, "and so does the auction")
	auction.free()


## `summary()` is PRIMITIVES ONLY, with each row's own summary nested under that row's
## key. A `Node`, `Resource` or `Object` in a summary is how a testable surface quietly
## stops being testable — and `ShopCounter.summary` embeds a whole `definition`, so
## this is the assertion that proves the screen FLATTENED it rather than passed it on.
func test_both_screen_summaries_are_primitives_only_with_nested_rows() -> void:
	_shop = _hero(&"reader", 4000)
	var market := _market(_shop)
	var reported := market.summary()
	assert_ne(reported.is_empty(), true, "the market has something to report")
	var offenders := _non_primitives(reported, "")
	# `str` over the ARRAY, not `"%s" % offenders`: Godot's `%` on an Array UNPACKS it
	# as the format argument list, so a single `%s` against a two-element array is
	# "not enough arguments for format string" — a runtime error, not a red assertion.
	var offenders_text := str(offenders)
	assert_eq(
		offenders.is_empty(), true, "the market summary holds only primitives: %s" % offenders_text
	)
	var rows := reported["rows"] as Array
	assert_ne(rows.is_empty(), true, "and each stall's own summary is nested under 'rows'")
	assert_eq(
		_non_primitives(rows[0] as Dictionary, "rows[0]").is_empty(),
		true,
		"including the row that carries the definition the facade embedded"
	)
	market.free()

	var bidder := _hero(&"auction_reader", BIDDER_PURSE)
	var auction := _auction(bidder)
	var read := auction.summary()
	assert_eq(_non_primitives(read, "").is_empty(), true, "and so does the auction's")
	auction.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and
## `ui_cancel` is DECLINED so the stack pops exactly as it pops every other screen. A
## screen that swallowed cancel would trap the player on a page that has verbs.
func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	for scene in [MARKET_SCENE, AUCTION_SCENE]:
		var screen := (scene as PackedScene).instantiate()
		for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
			assert_eq(screen.has_method(hook), true, "%s implements %s" % [scene, hook])
		screen.on_screen_shown()
		screen.on_screen_hidden()
		screen.focus_initial()
		assert_eq(screen.call(&"summary"), {}, "still empty, so a focus call invented nothing")

		screen.call(&"setup", _hero(&"hooked", 4000))
		assert_eq(screen.call(&"on_stack_input", null), false, "a null event is declined")
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		assert_eq(
			screen.call(&"on_stack_input", cancel), false, "cancel is declined so the stack pops"
		)
		var other := InputEventAction.new()
		other.action = &"ui_right"
		other.pressed = true
		assert_eq(screen.call(&"on_stack_input", other), false, "and so is everything else")
		screen.free()


## `ui_down` walks the SHOWN list and consumes only when it did something, and
## `ui_accept` buys the picked stall. One key, and the panel re-rendering between the
## two is what makes it readable rather than a guess.
func test_the_pick_walks_the_shown_list_and_accept_buys_the_picked_stall() -> void:
	_shop = _hero(&"keyboard", 4000)
	var screen := _market(_shop)
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_eq(screen.on_stack_input(down), true, "down picks the first stall")
	var picked := String(screen.summary()["selected_shop"])
	assert_ne(picked, "", "and something is picked")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(
		screen.on_stack_input(accept), true, "accept is consumed, because it bought something"
	)
	var after := screen.summary()
	assert_eq(bool(after["last_ok"]), true, "and the trade is published as primitives")
	assert_ne(
		int(after["last_coins"]), 0, "naming the coins that moved, so the page says what cost"
	)
	screen.free()


## Every authored stall is priced by the ONE reader, and the row prints that price
## rather than one it composed. Read from the shelf the facade published, so the
## assertion is about the panel owning the format rather than about a literal.
func test_the_shop_row_prints_the_figures_and_the_screen_formats_none() -> void:
	_shop = _hero(&"reader", 4000)
	var row := (SHOP_ROW_SCENE as PackedScene).instantiate() as MarketRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	var line := _shelf_row(SHOP_ID, &"alchemy_mist_herb")
	assert_ne(line, {}, "setup: the reagent row is priced")
	(
		row
		. show_shop(
			{
				"shop_id": String(SHOP_ID),
				"display_name": "Reader",
				"kind": "trader",
				"buys": ["alchemy_mist_herb"],
				"ok": true,
				"can_buy": true,
				"shelf": [line],
				"purse": 12,
				"funding": 34,
			}
		)
	)
	var shown := row.summary()
	assert_ne(shown, {}, "a priced stall fills it")
	assert_ne(
		String(shown["shelf_line"]).find(str(int(line["coins"]))),
		-1,
		"the row prints the authored charge, which the facade authored rather than the screen"
	)
	assert_ne(
		String(shown["purse_line"]).find("12"),
		-1,
		"and the stall's own purse, so a player reads the margin before trading"
	)
	assert_eq(
		String(shown["afford_line"]).to_lower(),
		"you can afford the cheapest of these",
		(
			"and the affordability sentence, which is the panel's own. Lower-cased before "
			+ "comparison because `String.capitalize()` is sentence-case: it leaves the "
			+ "interior words lower and only raises the first letter"
		)
	)
	row.free()


## The lot row publishes the high bidder and prints them, which is the fact the whole
## auction surface exists for. Asserted on a SYNTHETIC row so the case is about the
## panel's rendering rather than about a particular module fixture.
func test_the_lot_row_prints_the_high_bidder_and_a_lot_with_none_says_so() -> void:
	var row := (LOT_ROW_SCENE as PackedScene).instantiate() as AuctionLotRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	(
		row
		. show_lot(
			{
				"lot_id": "lot_hero_stone",
				"def_id": String(AUCTION_GOOD),
				"seller_id": "someone_else",
				"rarity": "rare",
				"price": 100,
				"required_bid": 110,
				"high_bid": "a_rival",
				"high_bid_amount": 210,
				"bid_count": 1,
				"closes_after": 3,
				"status": AuctionScreen.STATUS_OPEN,
				"can_bid": true,
			}
		)
	)
	var shown := row.summary()
	assert_ne(shown, {}, "a lot fills it")
	assert_ne(
		String(shown["high_line"]).find("a_rival"),
		-1,
		"the row PRINTS the high bidder's name — the fact no other surface published"
	)
	assert_ne(String(shown["high_line"]).find("210"), -1, "and the amount they stand at")
	assert_ne(
		String(shown["state_line"]).find("110"),
		-1,
		"and what the next bid has to be, which is what a bidder reads before pressing"
	)
	# A lot nobody has bid on is a different sentence, not an empty name.
	(
		row
		. show_lot(
			{
				"lot_id": "lot_quiet",
				"def_id": String(AUCTION_GOOD),
				"status": AuctionScreen.STATUS_OPEN,
				"required_bid": 10,
			}
		)
	)
	assert_eq(
		String(row.summary()["high_line"]),
		"No bids yet",
		"an unbid lot says so in words rather than printing nothing"
	)
	row.free()


## The route is REACHABLE, not merely shippable, for BOTH surfaces. A screen the
## composition root never mounts is reachable by nothing but this file, which is the
## shape the audit found. Asserted with the REAL `ScreenRoutes` API — keyed by id, with
## `id_for_scene` as the inverse (there is no `route_for_scene`).
func test_both_routes_are_published_and_bound_to_a_key() -> void:
	for pair in [
		[MARKET_SCENE, MARKET_ROUTE],
		[AUCTION_SCENE, AUCTION_ROUTE],
	]:
		var scene := pair[0] as PackedScene
		var route := StringName(pair[1])
		assert_eq(
			ScreenRoutes.id_for_scene(String(scene.resource_path)),
			route,
			"the route table mounts %s, and names it by id" % scene.resource_path
		)
		assert_eq(ScreenRoutes.has(route), true, "and '%s' is in the table" % route)
		assert_eq(
			ScreenRoutes.scene_of(route),
			String(scene.resource_path),
			"and the route and the loaded scene are the same file, in both directions"
		)
		assert_eq(scene.can_instantiate(), true, "so the path the table names loads")
		assert_ne(ScreenRoutes.node_of(route), "", "and the mounted node carries a name")
		var action := ScreenRoutes.action_of(route)
		assert_eq(
			InputMap.has_action(action), true, "and '%s' is declared in project.godot" % action
		)
		assert_eq(
			String(ScreenRoutes.route_for_action(action)),
			String(route),
			"and the action routes back to this route, so no key can open another screen"
		)


## And the page is REACHABLE from the composition root: the binding arms inject the
## seams. An unwired screen would refuse `no_market_seam` / `no_auction_seam` forever
## and every other case in this file would be measuring a seam nobody injected.
##
## Read CODE, not the file: `item_workbench_app.gd` documents these routes at length in
## docstrings that name every seam too, so a raw text scan would be asserting the
## comment rather than the wiring. Every scan in this file goes through `_code_only`,
## for the same reason `test_forage_surface.gd` strips comments before looking for
## `@onready`.
func test_the_binding_arms_inject_the_seams_the_screens_cannot_reach_themselves() -> void:
	var source := _code_only(ROOT_SCRIPT_PATH)
	assert_ne(source.is_empty(), true, "the composition root's source is readable")
	assert_eq(source.count("ROUTE_MARKET:"), 1, "the root binds the market route exactly once")
	assert_eq(source.count("ROUTE_AUCTION:"), 1, "and the auction route exactly once")
	# The market seam is `ShopCounter.at_location` by bare static name, and the two
	# verbs by the root's own methods (which resolve a counter the screen may not mint).
	assert_eq(
		source.count('Callable(ShopCounter, "at_location")'),
		1,
		"and it hands the screen `ShopCounter.at_location` itself, not a re-implementation"
	)
	assert_eq(
		source.count('"_market_buy"'), 1, "plus the buy verb, resolved against the counter cache"
	)
	assert_eq(source.count('"_market_sell"'), 1, "and the sell verb, which also carries the def")
	# The auction seam is `AuctionBids.bid` by bare static name — the whole reason this
	# route is half a consumer and the other half is by-name.
	assert_eq(
		source.count('Callable(AuctionBids, "bid")'),
		1,
		"and it hands the screen `AuctionBids.bid` itself, so the appetite arithmetic has one home"
	)
	# And the screens may not name any of it: `app/` is a `PRIVATE_UNIT`, so the seams
	# are the only door. Asserted from the shipped source, because that is the boundary
	# this file is the proof of.
	for path in [MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH]:
		var code := _code_only(path)
		for forbidden in ["ShopCounter", "AuctionBids", "ForageAction", "res://src/app/"]:
			assert_eq(
				code.contains(forbidden),
				false,
				(
					"%s names %s; ui/ may not name an app/ type, so the seam is the only door"
					% [path, forbidden]
				)
			)


## The two surfaces reach `market` by exactly the two roads there are, and which is
## which is the design rather than an accident.
##
## `rules.UI_MODULES` declares `"market": ["economy"]`, so `ui/` may name `MarketApi`
## — `tools/arch/enforce.py` checks `dep in rules.UI_MODULES` against the MODULE the
## reference resolves to, and `economy` has no key there, so `EconomyApi` by name from
## `ui/` would be an UNDECLARED module. The auction screen therefore lists BY NAME and
## bids by SEAM; the market screen reads its purse by name and needs BOTH seams,
## because `MarketApi.buy(shop_actor, player, rows)` takes a merchant `Actor` only
## `ShopCounter` (an `app/` type) can mint.
func test_the_auction_screen_reaches_the_verbs_by_the_only_two_roads_there_are() -> void:
	var auction := _code_only(AUCTION_SCRIPT_PATH)
	assert_eq(
		auction.count("MarketApi.list("),
		1,
		"the screen escrows BY NAME: every argument is the bound actor and two plain ids"
	)
	assert_eq(
		auction.count("MarketApi.summary(") >= 1,
		true,
		"and reads the facade's read model by name, exactly as the forage screen reads HoldingsApi"
	)
	# No `EconomyApi` anywhere: `economy` is the market MODULE's declared dependency, not
	# a grant to `ui/`.
	for path in [
		MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH
	]:
		assert_eq(
			_code_only(path).contains("EconomyApi"),
			false,
			(
				"%s names EconomyApi; `market: [economy]` is the module graph edge, not a ui/ grant"
				% path
			)
		)
	# The market screen reaches no verb by name, and says why.
	var market := _code_only(MARKET_SCRIPT_PATH)
	assert_eq(
		market.contains("MarketApi.buy(") or market.contains("MarketApi.sell("),
		false,
		"the market screen names no market verb: both take a shop Actor only app/ can mint"
	)
	assert_eq(
		market.count("MarketApi.summary(") >= 1,
		true,
		"so it reads the one thing the facade CAN hand it — the purse"
	)


## The screens name NO module interior and no path into a module; a panel calls the
## facade by bare name. `tools arch` checks the module side of that boundary; this
## checks the UI side, by reading the shipped source.
func test_the_screens_name_facades_and_nothing_else_from_either_module() -> void:
	for path in [MARKET_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		for interior in [
			"MarketState",
			"ShopDef",
			"ShopCatalog",
			"AuctionReadModel",
			"MarketTransfer",
			"MarketSpread",
			"EconomyValuation",
			"MarketWorldLedger",
		]:
			assert_eq(
				code.contains(interior),
				false,
				"%s names %s; ui/ may only reach the facade" % [path, interior]
			)
		assert_eq(
			code.contains("res://src/modules/"),
			false,
			"%s paths into no module; a panel calls the facade by bare name" % path
		)
	# The lot row is a row of the same data and names less than the screen does.
	var lot_row := _code_only(LOT_ROW_SCRIPT_PATH)
	for interior in ["MarketApi", "AuctionReadModel", "AuctionState", "AuctionBids"]:
		assert_eq(
			lot_row.contains(interior),
			false,
			"the lot row names %s either; it renders a dictionary and reaches nothing" % interior
		)


## The panels must resolve their widgets lazily, never in `@onready`, or a headless
## run that drives them with no scene tree binds nothing and renders nothing.
##
## Read as code, for the reason the scan above gives: these panels document the rule by
## naming the token, and a raw scan would fail on the very boundary it was written to
## prove.
func test_the_rows_bind_their_nodes_lazily_and_build_no_widgets_in_ready() -> void:
	for path in [
		SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH, MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH
	]:
		var code := _code_only(path)
		assert_eq(code.contains("@onready"), false, "%s declares no @onready" % path)
		assert_eq(code.contains("func _bind_nodes()"), true, "%s binds in _bind_nodes()" % path)
		assert_eq(
			code.count("get_node_or_null(") > 0 and code.count(".new()") == 0,
			true,
			"%s resolves lazily and mints no widget, which a scene mounts" % path
		)


## The last three bans, read off the SHIPPED screens: no `queue_free()` (a deferred
## free never runs under a runner driven from `SceneTree._initialize()`, so it leaks a
## screen's whole row pool for the life of the process), no `theme_override_*`, and no
## number formatting of its own.
##
## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`
##
## The rule is "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths", and what it protects is the FIGURES A PLAYER READS. A screen may still name
## a count it does not display: it grows its row pool with `row.name = "Lot%d"`, and a
## node's name in the scene tree is not an authored figure on a card. So the scan looks
## for a format in the same expression as an assignment to something a `Label` reads,
## which is the only place a formatted number reaches a player.
func test_the_screens_break_none_of_the_three_bans_the_ui_standard_states() -> void:
	for path in [
		MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH
	]:
		var code := _code_only(path)
		assert_eq(
			code.contains("queue_free"),
			false,
			"%s has no queue_free(): the runner never defers" % path
		)
		assert_eq(
			code.contains("theme_override_"), false, "%s styles itself; the theme owns style" % path
		)
		if path.ends_with("market_screen.gd") or path.ends_with("auction_screen.gd"):
			assert_eq(
				code.contains(".free()"), false, "%s frees nothing at all from a screen" % path
			)
		for sink in [".text =", "afford_line", "shelf_line", "high_line", "state_line"]:
			for format in ["%d", "%.1f", "%.2f"]:
				var line := ""
				for candidate in code.split("\n"):
					if candidate.contains(sink) and candidate.contains(format):
						line = candidate
						break
				assert_eq(
					line.is_empty(),
					true,
					"no formatted figure reaches a label in %s: %s%s" % [path, sink, format]
				)


# --- plumbing ----------------------------------------------------------------


## A stall that trades nowhere and buys nothing — the black market ADR 0100 names. Read
## off the CONTENT tree's own trader and rewritten with an empty `buys`, so the case
## exercises a real def rather than a hand-built one.
func _black_market_def() -> ShopDef:
	var source := ShopCatalog.instance().definition(SHOP_ID)
	assert_ne(source, null, "setup: the authored trader exists")
	var def := ShopDef.new()
	def.shop_id = &"test_black_market"
	def.display_name = "Test Black Market"
	def.kind = &"trader"
	def.location_id = SHOP_LOCATION
	def.capacity = 4
	def.buys = [] as Array[StringName]
	return def


## A lot listed without a screen, so a case that needs a lot ON THE BOARD can say so
## without a screen in the way. `MarketApi.list` is the same verb the screen calls by
## name, so the fixture cannot drift from the surface.
func screen_free_list(seller: Actor, instance_id: String) -> Dictionary:
	return MarketApi.list(seller, StringName(instance_id), 3)


## The row a stall fills on the page, or `{}`. Read off the screen's own `summary()`, not
## off the facade, so what the player can see and what the verdict describes are the same
## world.
func _row_for(screen: MarketScreen, shop_id: String) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if String((row as Dictionary).get("shop_id", "")) == shop_id:
			return row as Dictionary
	return {}


## The row a lot fills on the page, or `{}`. Same reason as `_row_for`.
func _lot_row_for(screen: AuctionScreen, lot_id: String) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if String((row as Dictionary).get("lot_id", "")) == lot_id:
			return row as Dictionary
	return {}


## Dotted paths inside `summary` whose value is not a primitive, a String/array, or a
## dictionary of the same. A returned node or resource is what makes a "testable
## surface" untestable.
func _non_primitives(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		var entries: Dictionary = value
		for key in entries:
			var child: Variant = entries[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
		return out
	if value is Array:
		var items: Array = value
		for index in items.size():
			out.append_array(_non_primitives(items[index], "%s[%d]" % [path, index]))
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)


## The shipped source of `path` with every comment removed.
##
## A `#` line, and everything from an inline `#` to end of line, is prose. Asserting on
## prose is worse than useless here: this suite's whole subject is a boundary BETWEEN
## what a script says about a module and what it calls, and a docstring naming a banned
## symbol would turn a real boundary check into a typo detector. Same shape as
## `tests/ui/test_forage_surface.gd:_code_only`.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
