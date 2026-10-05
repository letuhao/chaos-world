extends TestCase

## Shared kit for the floor-surface suite. NOT a suite itself: the runner discovers
## `test_*.gd` only (`run_tests.gd::_find_tests`), so this file is never executed on its
## own.
##
## `MarketApi.set_store` is PROCESS-WIDE and the runner shares ONE process across every
## suite, calling `teardown()` after EVERY test on whichever suite instance ran it. A
## floor left installed outlives the suite and is inherited by everything that runs
## later, so the store is released per-test rather than per-suite — the
## `market_surface_fixture.gd` rule restated for the same reason.

const FLOOR_SCENE := preload("res://src/ui/screens/floor_screen.tscn")
const DROP_ROW_SCENE := preload("res://src/ui/panels/floor_drop_row.tscn")

const FLOOR_SCRIPT_PATH := "res://src/ui/screens/floor_screen.gd"
const DROP_ROW_SCRIPT_PATH := "res://src/ui/panels/floor_drop_row.gd"
const ROOT_SCRIPT_PATH := "res://src/app/item_workbench_app.gd"

const FLOOR_ROUTE := &"floor"

## The numéraire. A literal, because `EconomyValuation.numeraire_id()` is a FUNCTION
## and a `const` may not call one. The floor moves goods, not coins, so this is only
## the fixture's purse.
const COIN := &"curr_spirit_coin"
## A reagent the hero can carry, so the drop verb has something real to leave behind.
const GOOD := &"alchemy_mist_herb"
## The room this suite drops things in. Any stable id will do: the floor is keyed by
## whatever the caller names, and the point under test is that the SCREEN forwards it.
const FLOOR_LOCATION := &"floor_surface_row"
## An authored reagent the reagent trader stocks, read off the content tree, so a
## retune of that stall's `location_id` cannot leave this suite probing a room the
## build no longer ships.
const SHOP_LOCATION := &"foundation_reagent_row"
const SHOP_ID := &"foundation_reagent_trader"
## A good with an authored worth, so `MarketApi.list` will escrow rather than refuse
## `lot_unpriced`. The same fixture the auction suites use.
const AUCTION_GOOD := &"currency_spirit_stone"
## Enough purse that `AuctionState.bid_ceiling` at the default 30% appetite clears the
## lot's opening.
const BIDDER_PURSE := 4000

## Every actor this suite creates. `Actor` is a `RefCounted`, so one built inside a
## helper is freed the moment that helper returns — the ledger stores ids, never
## references. Holding them is what `tests/modules/market/test_market_auction.gd` does.
var _held: Array[Actor] = []


func setup() -> void:
	# A floor is a WORLD fact (ADR 0101), so a fresh store is not belt-and-braces: it is
	# what makes one actor's drop visible to another and what lets a bidder see a
	# seller's lot.
	MarketApi.set_store(MarketWorldLedger.new())
	ShopCounter.reset()
	ShopCatalog.instance().reset()
	_held.clear()


func teardown() -> void:
	# Process-wide, and the runner calls this after EVERY test.
	ShopCounter.reset()
	ShopCatalog.instance().reset()
	MarketApi.set_store(null)
	_held.clear()


# --- fixtures ----------------------------------------------------------------


## A hero with a bag, an economy ledger and a market ledger, which is everything a
## drop, a take and a settle need. `Actor` is held, never returned.
func _hero(id: StringName, coins: int) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, 24)
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	if coins > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	_held.append(actor)
	return actor


## A hero carrying `quantity` of `GOOD`, so a drop has goods to take.
func _carrier(id: StringName, quantity: int) -> Actor:
	var actor := _hero(id, 0)
	ItemsApi.inventory(actor).add(Crafting.resolve(GOOD), quantity)
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


## The floor screen bound to `hero` and pointed at `location`. **No seam is bound**,
## because the floor route needs none: `market` is a declared `UI_MODULES` grant and
## every verb takes only the bound actor plus plain ids.
func _floor(hero: Actor, location: StringName = FLOOR_LOCATION) -> FloorScreen:
	var screen := (FLOOR_SCENE as PackedScene).instantiate() as FloorScreen
	screen.setup(hero)
	screen.at_location(location)
	return screen


## The auction screen bound to `hero`, with BOTH seams wired exactly as the
## `ROUTE_AUCTION` arm wires them: the bare static function for the bid, and the
## bidder resolver the root hands over.
func _auction(hero: Actor) -> AuctionScreen:
	var screen := _auction_free(hero)
	screen.bind_auction(Callable(AuctionBids, "bid"))
	return screen


## The auction screen with the bid seam wired but NO settlement seam — the state the
## route mounts in before `bind_settlement` runs, and the one a caller gets if the
## binding arm is deleted.
func _auction_free(hero: Actor) -> AuctionScreen:
	var screen := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	screen.setup(hero)
	return screen


## The `bidder_id -> Actor` resolver a composition root hands the auction screen, over
## the actors this suite minted. A real resolution rather than a constant, so a lot
## naming a bidder nobody minted answers null — the branch `settle_lot` walks past.
func _resolver_over(actors: Array) -> Callable:
	return func(bidder_id: String) -> Actor:
		for entry in actors:
			if String((entry as Actor).id) == bidder_id:
				return entry as Actor
		return null


# --- plumbing ----------------------------------------------------------------


## The drop ids on the floor at `location`, read through the WORLD READ MODEL rather
## than through `MarketApi.state`, whose actor mirror goes stale the moment a second
## party touches the ledger.
func _floor_entries(location: StringName = FLOOR_LOCATION) -> Array:
	var reader := _hero(&"a_floor_reader", 0)
	var floor := MarketApi.summary(reader).get("floor", {}) as Dictionary
	return (floor.get(String(location), []) as Array) if location != &"" else []


## The entry with `drop_id`, or `{}` so a broken fixture turns the NEXT assertion red
## with a message rather than aborting this one halfway through.
func _entry(drop_id: String, location: StringName = FLOOR_LOCATION) -> Dictionary:
	for row in _floor_entries(location):
		if String((row as Dictionary).get("drop_id", "")) == drop_id:
			return row as Dictionary
	return {}


## Every lot in the world as the READ MODEL sees them.
func _lots() -> Array:
	var reader := _hero(&"a_lot_reader", 0)
	return MarketApi.summary(reader).get("lots", []) as Array


## The lot with `lot_id`, or `{}`.
func _lot(lot_id: String) -> Dictionary:
	for row in _lots():
		if String((row as Dictionary).get("lot_id", "")) == lot_id:
			return row as Dictionary
	return {}


## The row a drop fills on the page, or `{}`. Read off the screen's own `summary()`, not
## off the facade, so what the player can see and what the verdict describes are the
## same world.
func _row_for(screen: FloorScreen, drop_id: String) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if String((row as Dictionary).get("drop_id", "")) == drop_id:
			return row as Dictionary
	return {}


## The row a lot fills on the page, or `{}`. Same reason as `_row_for`.
func _lot_row_for(screen: AuctionScreen, lot_id: String) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if String((row as Dictionary).get("lot_id", "")) == lot_id:
			return row as Dictionary
	return {}


## How many of `rows` carry `key` with the truthy value `value`. A count rather than a
## membership test because "exactly one of them is on a clock" is the claim being made, and
## `any()` would also pass with three.
func _count_where(rows: Array, key: String, value: Variant = true) -> int:
	var found := 0
	for row in rows:
		if (row as Dictionary).get(key, null) == value:
			found += 1
	return found


## The one decaying row on the page, or `{}`. A separate accessor rather than a search
## parameter so a caller cannot accidentally pick which row it means.
func _rotting_row(screen: FloorScreen) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if bool((row as Dictionary).get("decaying", false)):
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
## Asserting on prose is worse than useless here: this suite's whole subject is a
## boundary BETWEEN what a script says about a module and what it calls, and a
## docstring naming a banned symbol would turn a real boundary check into a typo
## detector. Same shape as `test_market_surface.gd:_code_only` and
## `test_forage_surface.gd:_code_only`.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
