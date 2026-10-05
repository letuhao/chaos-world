extends TestCase

## Shared kit for the two halves of the market-surface suite. NOT a suite itself: the
## runner discovers `test_*.gd` only (`run_tests.gd::_find_tests`), so this file is
## never executed on its own.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every scene preload, path constant, `setup()`/`teardown()` and private helper
## the cases use now lives here, which both halves `extends`. No state is duplicated
## between them.
##
## `setup()` / `teardown()` MUST live here rather than in one half. `MarketApi.set_store`
## and `ShopCounter's counter cache are PROCESS-WIDE, and the runner shares ONE process
## across every suite, calling `teardown()` after EVERY test on whichever suite instance
## ran it. A counter left installed holds a live `Actor` with a realized `Inventory`
## alive until the engine shuts down, which ObjectDB then reports as leaked instances at
## exit with every assertion green -- so a store installed by one half and cleared by the
## other outlives the suite and is inherited by everything that runs later.
##
## ## Nothing leaks
##
## A shop counter left installed holds a live `Actor` with a realized `Inventory`
## alive until the engine shuts down, which ObjectDB then reports as leaked instances
## at exit with every assertion green. So the store and the counters are released
## per-test, not per-suite.
##
## The player-facing half is `test_market_surface.gd`. The screen-contract and
## structural-pin half is `test_market_surface_contract.gd`.
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
