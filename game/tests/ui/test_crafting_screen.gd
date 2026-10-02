extends TestCase

## The crafting screen (ADR 0043). `ItemsApi.craft` had no UI caller anywhere, so
## every realm pill was unmakeable: a player could be told exactly which item a
## breakthrough gate wanted and have no way to produce it (DEF-0057).
##
## Recipes are pushed in as plain dictionaries because `RecipeDef` belongs to the
## `items` module and `ui/` may only reach a module through its facade.

const SCREEN := "res://src/ui/screens/crafting_screen.tscn"


func _screen() -> CraftingScreen:
	return (load(SCREEN) as PackedScene).instantiate() as CraftingScreen


func _actor() -> Actor:
	var actor := Actor.new(&"crafter", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 128)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 999
	ItemsApi.inventory(actor).add(def, quantity)


## A real authored recipe, loaded the way a composition root would push it.
## `Crafting.resolve` reads item definitions off disk, so a recipe naming invented
## ids is refused at the output lookup rather than at the gate — which would test
## the wrong half of the screen.
const RECIPE_PATH := "res://data/recipes/A1_divine_abbatoir_aged_alt_recipe.tres"
const RECIPE_ID := "A1_divine_abbatoir_aged_alt_recipe"
const RECIPE_OUTPUT := &"A1_divine_abbatoir_aged"


## Every input the authored recipe names, so a test stocks what it actually needs
## rather than a hardcoded count that drifts when the recipe changes.
func _recipe_inputs() -> Array:
	var def: RecipeDef = load(RECIPE_PATH)
	return def.inputs


func _stock_all_inputs(actor: Actor) -> void:
	for input_id in _recipe_inputs():
		_stock(actor, input_id, 1)


## The recipe as the composition root hands it over: readable fields for the
## screen, plus the object the facade will accept.
func _pill_recipe() -> Dictionary:
	var def: RecipeDef = load(RECIPE_PATH)
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"station": String(def.station),
		"inputs": def.inputs,
		"outputs": def.outputs,
		"resource": def,
	}


# --- Headless contract ------------------------------------------------------


func test_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not partial")
	screen.free()


func test_it_lists_the_recipes_it_is_given() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.set_recipes([_pill_recipe()])
	var view := screen.summary()
	assert_eq(view.get("recipe_count", 0), 1, "one recipe offered")
	var recipes: Array = view.get("recipes", [])
	assert_eq(recipes.size(), 1, "one recipe row")
	assert_eq(recipes[0].get("id", ""), "A1_divine_abbatoir_aged_alt_recipe", "id is reported")
	assert_eq(recipes[0].get("outputs", []), ["A1_divine_abbatoir_aged"], "outputs reported")
	screen.free()


func test_the_first_recipe_is_selected_by_default() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.set_recipes([_pill_recipe()])
	assert_eq(
		screen.summary().get("selected", ""),
		"A1_divine_abbatoir_aged_alt_recipe",
		"first is offered"
	)
	screen.free()


func test_selecting_an_unknown_recipe_is_refused() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.select_recipe(&"nope"), false, "a typo is refused, not silently kept")
	assert_eq(
		screen.summary().get("selected", ""),
		"A1_divine_abbatoir_aged_alt_recipe",
		"selection unchanged"
	)
	screen.free()


# --- The gate a craft is refused by -----------------------------------------


func test_a_recipe_with_no_inputs_held_is_not_craftable() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.craftable_ids(), [], "nothing craftable with an empty inventory")
	var missing: Array = screen.summary().get("missing", [])
	assert_eq(missing.size(), _recipe_inputs().size(), "every input reported missing")
	screen.free()


func test_a_fully_stocked_recipe_becomes_craftable() -> void:
	var screen := _screen()
	var actor := _actor()
	_stock_all_inputs(actor)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.craftable_ids(), [RECIPE_ID], "stocked recipe is craftable")
	assert_eq(screen.summary().get("missing", []).size(), 0, "nothing missing")
	screen.free()


# --- Crafting ---------------------------------------------------------------


func test_crafting_produces_the_output_through_the_facade() -> void:
	var screen := _screen()
	var actor := _actor()
	_stock_all_inputs(actor)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.act_craft_selected(), true, "the craft succeeded")
	assert_eq(
		ItemsApi.has_item(actor, RECIPE_OUTPUT), true, "the crafted item reached the inventory"
	)
	assert_eq(screen.summary().get("tone", ""), "ok", "the outcome is reported")
	screen.free()


func test_a_refused_craft_consumes_nothing() -> void:
	var screen := _screen()
	var actor := _actor()
	var partial: StringName = _recipe_inputs()[0]
	_stock(actor, partial, 1)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.act_craft_selected(), false, "one input is short")
	assert_eq(ItemsApi.has_item(actor, partial), true, "the held input is untouched by a refusal")
	assert_eq(screen.summary().get("tone", ""), "error", "the refusal is explained")
	screen.free()


func test_crafting_by_id_selects_then_crafts() -> void:
	var screen := _screen()
	var actor := _actor()
	_stock_all_inputs(actor)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.act_craft(&"A1_divine_abbatoir_aged_alt_recipe"), true, "crafted by id")
	assert_eq(screen.act_craft(&"nope"), false, "an unknown id is refused")
	screen.free()


func test_crafting_without_an_actor_is_refused() -> void:
	var screen := _screen()
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.act_craft_selected(), false, "no actor, no craft")
	# With no actor `summary()` is empty by contract, so the refusal is reported
	# through the message the screen still holds rather than through a half-built
	# view a test could misread as state.
	assert_eq(screen.summary(), {}, "no actor means no view")
	screen.free()


func test_a_view_without_a_resource_refuses_rather_than_reaching_past_the_facade() -> void:
	## The screen may not build a `RecipeDef` itself, so a recipe pushed as a bare
	## view is listed and explained but cannot be crafted (DEF-0067).
	var screen := _screen()
	var actor := _actor()
	_stock_all_inputs(actor)
	screen.setup(actor)
	(
		screen
		. set_recipes(
			[
				{
					"id": "view_only",
					"display_name": "View Only",
					"station": "alchemy",
					"inputs": _recipe_inputs(),
					"outputs": [RECIPE_OUTPUT],
				}
			]
		)
	)
	assert_eq(screen.craftable_ids(), ["view_only"], "inputs are met")
	assert_eq(screen.act_craft_selected(), false, "but no resource was supplied")
	assert_eq(ItemsApi.has_item(actor, RECIPE_OUTPUT), false, "nothing was made")
	screen.free()
