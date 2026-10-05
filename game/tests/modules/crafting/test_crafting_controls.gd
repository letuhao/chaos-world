extends TestCase

## The CRAFTING surface, driven through the buttons a player presses.
##
## `test_crafting_screen.gd` calls `act_craft_selected()` directly. That proves the
## handler works and proves nothing about the rendered `CraftButton`: a screen whose
## button was never connected renders it, lists every recipe as craftable, and
## refuses on press — while every direct call in that suite stays green.
##
## So every case here presses `%CraftButton` or one of the scene's own
## `%Recipe<N>Button` rows, and asserts an OBSERVABLE OUTCOME: the crafted output
## reached the bag, a refusal consumed nothing, or the selection the pane shows
## changed.
##
## ## Why two real recipes and not one offered twice
##
## The row press is asked "does the selection follow the row?", and the craft is
## asked "does the craft follow the selection?". One answer cannot settle both: a
## screen that always crafted the FIRST row would pass a selection assertion that
## only checked `selected` changed, and pass a craft assertion made against the
## row that was already selected. So the two rows here are two authored recipes
## with DIFFERENT inputs and DIFFERENT outputs, and the crafted item names which
## one ran.
##
## Recipes are pushed in as the composition root pushes them — readable fields plus
## the `resource` the facade accepts — because `RecipeDef` belongs to the `items`
## module and `ui/` may only reach a module through its facade.

const FIRST_RECIPE := "res://data/recipes/blade_iron_recipe.tres"
const FIRST_OUTPUT := &"blade_iron"
const SECOND_RECIPE := "res://data/recipes/bow_yew_recipe.tres"
const SECOND_OUTPUT := &"bow_yew"
## How many rows the scene composes, so "the row a player presses" is a scene fact
## rather than an assumption about how many recipes this suite offers.
const SCENE_ROWS := 6

var _rig: ItemSurfaceRig = null


func setup() -> void:
	# A per-SUITE floor, so it is the SMALLEST body here: the two-assertion
	# spend case. It catches a body that died mid-way, which records neither a
	# pass nor a failure and so reports green while having skipped its proof.
	expect_assertions(2)
	_rig = ItemSurfaceRig.new()


func teardown() -> void:
	_rig.release()


## The crafting scene, mounted and bound to `actor` with both authored recipes
## offered in a known order: `blade_iron_recipe` first, `bow_yew_recipe` second.
func _crafting(actor: Actor) -> CraftingScreen:
	var screen := _rig.screen(ItemSurfaceRig.CRAFTING_SCENE) as CraftingScreen
	if screen == null:
		return null
	screen.setup(actor)
	screen.set_recipes([_recipe(FIRST_RECIPE), _recipe(SECOND_RECIPE)])
	return screen


## An authored recipe as the composition root hands it over: readable fields for
## the screen, plus the object the facade will accept.
func _recipe(path: String) -> Dictionary:
	var def: RecipeDef = load(path)
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"station": String(def.station),
		"inputs": def.inputs,
		"outputs": def.outputs,
		"resource": def,
	}


## Stock every input of `path` through the facade, and report how many landed.
##
## Definitions are AUTHORED rather than fabricated, because `display_name` only
## exists on a real one: a fabricated `ItemDef.new()` carries an empty name, so a
## screen reading names from it correctly falls back to the id and the case passes
## for the wrong reason.
func _stock_inputs(actor: Actor, path: String) -> int:
	var def: RecipeDef = load(path)
	var stocked := 0
	for input_id in def.inputs:
		if _rig.stock_authored(actor, input_id, 1):
			stocked += 1
	return stocked


## How many units of `path`'s inputs the hero holds in total.
func _held_inputs(actor: Actor, path: String) -> int:
	var def: RecipeDef = load(path)
	var held := 0
	for input_id in def.inputs:
		held += ItemsApi.inventory(actor).count(input_id)
	return held


# --- The craft, through the button -------------------------------------------


## The claim: pressing the rendered Craft button produces the item. The observable
## outcome is the OUTPUT IN THE BAG, not the press's return value — a button wired
## to nothing changes nothing a player can see.
func test_pressing_craft_puts_the_output_in_the_bag() -> void:
	var actor := _rig.hero(&"crafter", 128)
	assert_eq(_stock_inputs(actor, FIRST_RECIPE) > 0, true, "the inputs are stocked")
	var screen := _crafting(actor)
	assert_ne(screen, null, "the crafting scene mounts")
	assert_eq(ItemsApi.has_item(actor, FIRST_OUTPUT), false, "nothing is made yet")
	assert_eq(_rig.press(screen, "%CraftButton"), true, "the Craft control is pressable")
	assert_eq(
		ItemsApi.has_item(actor, FIRST_OUTPUT),
		true,
		"the observable outcome: the crafted item reached the inventory"
	)
	assert_eq(ItemsApi.inventory(actor).count(FIRST_OUTPUT), 1, "exactly one was made")
	assert_eq(String(screen.summary()["tone"]), "ok", "and the outcome is reported")


## The inputs are the cost, so a craft that left them in the bag would be a
## free lunch no assertion above would notice.
func test_pressing_craft_spends_the_recipe_inputs() -> void:
	var actor := _rig.hero(&"crafter", 128)
	_stock_inputs(actor, FIRST_RECIPE)
	var screen := _crafting(actor)
	var before := _held_inputs(actor, FIRST_RECIPE)
	assert_eq(_rig.press(screen, "%CraftButton"), true, "the Craft control is pressable")
	assert_eq(
		_held_inputs(actor, FIRST_RECIPE),
		before - 1,
		"one unit was spent: an unspent craft would hand out the item for free"
	)


## The negative case, and the one that matters most: a screen that offers a craft
## it cannot perform. With nothing stocked the row must not read "Ready", and the
## press must refuse while consuming nothing.
func test_a_short_recipe_refuses_the_press_and_consumes_nothing() -> void:
	var actor := _rig.hero(&"crafter", 128)
	var screen := _crafting(actor)
	var rows: Array = screen.summary()["recipes"]
	assert_eq(bool((rows[0] as Dictionary)["craftable"]), false, "the row is not craftable")
	assert_eq(String((rows[0] as Dictionary)["craft_state"]), "short", "and it says short")
	assert_eq(_rig.press(screen, "%CraftButton"), true, "the control is still live")
	assert_eq(ItemsApi.has_item(actor, FIRST_OUTPUT), false, "no output was made")
	assert_eq(String(screen.summary()["tone"]), "error", "the refusal is reported")
	assert_eq(_held_inputs(actor, FIRST_RECIPE), 0, "and nothing held was touched")


# --- The row buttons: how a recipe is chosen ---------------------------------


## Recipes are chosen by pressing their row, so a row button that never reached
## the handler leaves the selection on whatever the screen opened on.
func test_pressing_a_recipe_row_selects_that_recipe() -> void:
	var actor := _rig.hero(&"crafter", 128)
	var screen := _crafting(actor)
	var def: RecipeDef = load(SECOND_RECIPE)
	assert_eq(String(screen.summary()["selected"]), String(load(FIRST_RECIPE).id), "row 0 is open")
	assert_eq(_rig.button(screen, "%Recipe1Button").disabled, false, "row 1 is pressable")
	assert_eq(_rig.press(screen, "%Recipe1Button"), true, "the row press lands")
	assert_eq(
		String(screen.summary()["selected"]),
		String(def.id),
		"the observable outcome: the pressed row is now the selection"
	)


## Which the previous case cannot settle: a screen that always crafted the FIRST
## row would still report a changed selection. So the craft must follow the
## selection, and the OUTPUT names which recipe ran.
func test_craft_acts_on_the_recipe_the_row_press_selected() -> void:
	var actor := _rig.hero(&"crafter", 128)
	_stock_inputs(actor, SECOND_RECIPE)
	var screen := _crafting(actor)
	assert_eq(_rig.press(screen, "%Recipe1Button"), true, "the second row is pressed")
	assert_eq(_rig.press(screen, "%CraftButton"), true, "Craft is pressable")
	assert_eq(
		ItemsApi.has_item(actor, SECOND_OUTPUT),
		true,
		"the SELECTED recipe's output is what was made"
	)
	assert_eq(
		ItemsApi.has_item(actor, FIRST_OUTPUT),
		false,
		"and the row that was NOT selected made nothing, so the selection really decided"
	)


## The row buttons exist at all. Without this, a case above could fail for a reason
## that has nothing to do with crafting — a scene that composed no rows.
func test_every_recipe_row_the_scene_composes_is_a_button_on_the_screen() -> void:
	var actor := _rig.hero(&"crafter", 128)
	var screen := _crafting(actor)
	var live := 0
	for index in SCENE_ROWS:
		var row := _rig.button(screen, "%%Recipe%dButton" % index)
		assert_ne(row, null, "row %d is a button on the screen" % index)
		if row != null and not row.disabled:
			live += 1
	assert_eq(live > 0, true, "at least one row is pressable for the offered recipes")


## The held counts are what make a craft decidable, so a detail pane reading "0
## held" for a stocked recipe would send a player to gather what they already own.
## Read from the rendered Label, because that is the surface the player looks at.
func test_the_detail_pane_counts_what_the_actor_actually_holds() -> void:
	var actor := _rig.hero(&"crafter", 128)
	var stocked := _stock_inputs(actor, FIRST_RECIPE)
	var screen := _crafting(actor)
	var detail := screen.get_node_or_null("%DetailLabel") as Label
	assert_ne(detail, null, "the detail label exists")
	assert_eq(stocked, 1, "the single input was stocked")
	assert_eq(
		detail.text.contains("(1 held)"),
		true,
		"the pane reports the held count a craft decision needs: %s" % detail.text
	)
	assert_eq(
		detail.text.contains("Ready to craft"),
		true,
		"and with its inputs met it says the craft is ready: %s" % detail.text
	)


## The refusal, read where a player reads it. The status label is the screen's own
## outcome line, and a refusal that renders as an empty line is the defect the
## three-state craft vocabulary exists to prevent.
func test_a_refused_press_says_so_on_the_status_line() -> void:
	var actor := _rig.hero(&"crafter", 128)
	var screen := _crafting(actor)
	var status := screen.get_node_or_null("%StatusLabel") as Label
	assert_ne(status, null, "the status label exists")
	assert_eq(_rig.press(screen, "%CraftButton"), true, "the press lands")
	assert_eq(
		status.text.begins_with("Missing"),
		true,
		"the outcome line names the shortfall rather than trailing off: '%s'" % status.text
	)
