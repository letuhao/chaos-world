extends TestCase

## The crafting screen (ADR 0043). `ItemsApi.craft` had no UI caller anywhere, so
## every realm pill was unmakeable: a player could be told exactly which item a
## breakthrough gate wanted and have no way to produce it (DEF-0057).
##
## Recipes are pushed in as plain dictionaries because `RecipeDef` belongs to the
## `items` module and `ui/` may only reach a module through its facade.

const SCREEN := "res://src/ui/screens/crafting_screen.tscn"

## A real authored recipe, loaded the way a composition root would push it.
## `Crafting.resolve` reads item definitions off disk, so a recipe naming invented
## ids is refused at the output lookup rather than at the gate — which would test
## the wrong half of the screen.
const RECIPE_PATH := "res://data/recipes/A1_divine_abbatoir_aged_alt_recipe.tres"
const RECIPE_ID := "A1_divine_abbatoir_aged_alt_recipe"
const RECIPE_OUTPUT := &"A1_divine_abbatoir_aged"


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


## Stock an AUTHORED definition, keeping its `display_name`.
##
## `_stock` above fabricates a bare `ItemDef.new()`, which is right for testing
## counts and wrong for testing names: a fabricated def carries an empty
## `display_name`, so a screen reading names from it correctly falls back to the id
## and the test passes for the wrong reason. This is the same trap the headless
## driver documents when it switched from fabricated defs to `Crafting.resolve`.
func _stock_def(actor: Actor, def: ItemDef, quantity: int) -> void:
	ItemsApi.inventory(actor).add(def, quantity)


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


## The worst branch on this screen, and the one the standard calls out: a refusal
## rendered identically to an offer.
##
## With no actor there is no inventory to read, and `_missing_of` returned an empty
## list -- the same value a fully-stocked recipe returns. So `craftable_ids()` listed
## every recipe, the row tooltip read "Ready", and the detail pane read "Ready to
## craft". A player who pressed one got a refusal, having been told it would work.
func test_an_unknown_craft_state_is_never_rendered_as_ready() -> void:
	var screen := _screen()
	screen.set_recipes([_pill_recipe()])
	assert_eq(screen.craftable_ids(), [], "nothing is craftable without an actor")
	assert_eq(screen.is_craftable(StringName(RECIPE_ID)), false, "nor this one, by id")
	# `summary()` is `{}` with no actor by contract, so the craft state is read from
	# the detail pane -- the surface a player would actually be looking at.
	var detail := screen.get_node_or_null("%DetailLabel") as Label
	assert_eq(
		detail.text.contains("Ready to craft"),
		false,
		"the detail pane must not offer a craft it cannot check: %s" % detail.text
	)
	assert_eq(detail.text.contains("Inputs unknown"), true, "it says so instead")
	screen.free()


## The held count is what makes a craft decidable, and reading it used to call
## `ItemsApi.inventory` with a null actor, which dereferences and raises a script
## error inside the module. A refusal must render as a refusal, not as a crash.
func test_the_detail_pane_survives_having_no_actor() -> void:
	var screen := _screen()
	screen.set_recipes([_pill_recipe()])
	var detail := screen.get_node_or_null("%DetailLabel") as Label
	assert_ne(detail, null, "the detail label exists")
	assert_eq(
		detail.text.contains("held unknown"),
		true,
		"an unreadable inventory says unknown rather than claiming zero held: %s" % detail.text
	)
	screen.free()


## A row's tooltip and the recipe block are the only places a player learns a craft
## will be refused before pressing it.
func test_a_short_recipe_says_what_is_missing() -> void:
	var screen := _screen()
	var actor := _actor()
	ItemsApi.attach(actor, 128)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	var rows: Array = screen.summary().get("recipes", [])
	assert_ne(rows.size(), 0, "the recipe is listed")
	var row: Dictionary = rows[0]
	assert_eq(row.get("craftable", true), false, "nothing is stocked, so not craftable")
	assert_eq(row.get("craft_state", ""), "short", "and the state says short")
	var detail := screen.get_node_or_null("%DetailLabel") as Label
	assert_eq(
		detail.text.contains("Missing:"),
		true,
		"the detail pane names the shortfall: %s" % detail.text
	)
	assert_eq(detail.text.contains("Ready to craft"), false, "and never claims ready")
	screen.free()


## The detail pane printed raw ids where the row above it printed a display name, so
## one screen showed an item id and its authored name for the same item side by side.
## The row label and the detail text must agree.
##
## Uses AUTHORED definitions, because `display_name` only exists on a real one: a
## fabricated `ItemDef.new()` carries an empty name, so stocking those would make
## this test pass for the wrong reason.
func test_the_detail_pane_names_items_rather_than_printing_their_ids() -> void:
	var screen := _screen()
	var actor := _actor()
	_stock_authored_inputs(actor)
	screen.setup(actor)
	screen.set_recipes([_pill_recipe()])
	var detail := screen.get_node_or_null("%DetailLabel") as Label
	assert_ne(detail, null, "the detail label exists")
	var authored := _authored_input()
	assert_ne(authored, null, "the recipe names an authored input")
	var named := L.t(String(authored.display_name))
	assert_ne(named, "", "and that input has a display name")
	assert_ne(named, String(authored.id), "which differs from its id")
	assert_eq(
		detail.text.contains("Costs: %s" % String(authored.id)),
		false,
		"a cost is named, not printed as its id: %s" % detail.text
	)
	assert_eq(
		detail.text.contains(named), true, "the authored name reaches the player: %s" % detail.text
	)
	screen.free()


## The first authored input the recipe names, resolved the way the game resolves it.
func _authored_input() -> ItemDef:
	for input_id in _recipe_inputs():
		var def := Crafting.resolve(input_id)
		if def != null:
			return def
	return null


## Stock the recipe's inputs with their real definitions, so the screen has a
## `display_name` to read and a held count to report.
func _stock_authored_inputs(actor: Actor) -> void:
	for input_id in _recipe_inputs():
		var def := Crafting.resolve(input_id)
		if def != null:
			_stock_def(actor, def, 1)


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
