extends TestCase

## ADR 0167 / BL-0815: a CRAFT is an action and costs world time, end to end.
##
## The crafting screen asks the composition root through `CraftingBridge`; the root pays
## the periods through `advance_world` — the same ONE dispatcher the wait button and the
## retreat end in. This is the second consumer of ADR 0167's period-scale class, after the
## season-scale retreat.
##
## ## Never drive the thing under test
##
## The app is the REAL `ItemWorkbenchApp` scene mounted by `SeamHarness` (the retreat
## suite's harness), and the screen is the real scene instantiated from disk. The figures
## asserted are the world fold's own running total, read through the composition root's own
## `world_summary`, never a number this suite produced.

const SCREEN := "res://src/ui/screens/crafting_screen.tscn"
## A shipped recipe whose inputs are stockable, so a craft can actually LAND.
const RECIPE := "res://data/recipes/A1_divine_abbatoir_base_recipe.tres"
const INPUTS: Array[StringName] = [&"Q1_divine_courier_crust", &"divine_primordial_tablet"]

var _harness: SeamHarness = null
var _app: ItemWorkbenchPlay = null


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchPlay


func teardown() -> void:
	# `WorldStage`'s mounted body is a process-wide static, so a mount left behind would
	# publish a freed `PlayerAdapter` to every suite after this one.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


func _booted() -> bool:
	if _app == null:
		return false
	assert_eq(
		_harness.boot_error, "", "the real ItemWorkbenchApp scene boots, or nothing below is proven"
	)
	return _harness.boot_error == ""


func _periods() -> int:
	return int((_app.call(&"world_summary") as Dictionary).get("periods", 0))


func _recipe() -> Resource:
	return load(RECIPE) as Resource


## Stock every input the recipe needs, so the craft can land.
func _stock(actor: Actor) -> void:
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	for input_id in INPUTS:
		var def := Crafting.resolve(input_id)
		assert_ne(def, null, "input %s resolves to a real def" % input_id)
		if def != null:
			inventory.add(def, 1)


# --- The production door ------------------------------------------------------


func test_the_mounted_root_publishes_the_craft_verb() -> void:
	if not _booted():
		return
	assert_eq(_app.has_method(&"craft_with_time"), true, "the play half publishes the craft verb")
	assert_eq(
		_app.has_method(&"advance_world"),
		true,
		"and the verb it routes through is the same clock verb the wait button drives"
	)


# --- The cost -----------------------------------------------------------------


## THE COST. A craft that lands pays the authored periods, measured on the fold's own
## running total rather than on the report's `paid` key.
func test_a_landed_craft_costs_world_time() -> void:
	if not _booted():
		return
	_stock(_harness.actor)
	var before := _periods()

	var report := _app.call(&"craft_with_time", _recipe()) as Dictionary

	assert_eq(bool(report.get("ok", false)), true, "the craft lands: %s" % report.get("reason", ""))
	assert_eq(
		_periods() - before,
		ItemWorkbenchPlay.CRAFT_PERIODS,
		"the world moved by the authored craft cost"
	)
	assert_eq(
		int(report.get("paid", 0)),
		ItemWorkbenchPlay.CRAFT_PERIODS,
		"and the report names the same figure the world moved"
	)


## A REFUSED craft costs nothing (ADR 0044): the time is paid only once the craft landed,
## so a recipe the actor cannot afford never ages the world for work that did not happen.
func test_a_refused_craft_pays_nothing() -> void:
	if not _booted():
		return
	var before := _periods()

	var report := _app.call(&"craft_with_time", _recipe()) as Dictionary

	assert_eq(bool(report.get("ok", true)), false, "an unstocked craft is refused")
	assert_eq(String(report.get("reason", "")), "craft_refused", "and refused by name")
	assert_eq(int(report.get("paid", 0)), 0, "paying nothing")
	assert_eq(_periods(), before, "and the world did not move")


# --- The screen asks the root, not the facade --------------------------------


## THE ROUTING. The screen calls the bridge's craft callable and does NOT reach
## `ItemsApi.craft` directly — a spy proves the call went through the clock seam.
func test_the_screen_routes_the_craft_through_the_bridge() -> void:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CraftingScreen
	assert_ne(screen, null, "crafting_screen.tscn roots a CraftingScreen")
	var actor := Actor.new(&"craft_ui_hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, 64)
	_stock(actor)
	screen.call("setup", actor)
	screen.call("set_recipes", RecipeCatalog.offerable(actor))
	var calls: Array = []
	var bridge := CraftingBridge.new()
	bridge.craft = func(recipe: Resource) -> Dictionary:
		calls.append(recipe)
		return {"ok": true, "reason": "", "made": true, "paid": ItemWorkbenchPlay.CRAFT_PERIODS}
	screen.call("set_bridge", bridge)

	assert_eq(screen.call("act_craft_selected"), true, "the craft press lands")
	assert_eq(calls.size(), 1, "and it went through the bridge, not the facade directly")
	screen.free()
