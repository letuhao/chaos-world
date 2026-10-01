extends TestCase

## Crafting must resolve an ItemDef by id. Items live at
## res://data/items/<category>/<id>.tres, so a lookup that omits <category> resolves
## nothing and craft() silently yields no output.

const RECIPE := "res://data/recipes/jade_pill_recipe.tres"
const HERB := "res://data/items/material/spirit_herb.tres"
const ORE := "res://data/items/material/jade_ore.tres"


func _stocked_inventory() -> Inventory:
	var inventory := Inventory.new()
	inventory.add(load(HERB), 1)
	inventory.add(load(ORE), 1)
	return inventory


func test_load_item_resolves_through_category_folder() -> void:
	var def := Crafting.load_item(&"spirit_herb")
	assert_eq(def == null, false, "resolves a material item")
	if def == null:
		return
	assert_eq(def.id, &"spirit_herb", "id")
	assert_eq(def.category, ItemCategory.MATERIAL, "category")


func test_load_item_resolves_a_second_category() -> void:
	var def := Crafting.load_item(&"jade_pill")
	assert_eq(def == null, false, "resolves a consumable item")
	if def == null:
		return
	assert_eq(def.category, ItemCategory.CONSUMABLE, "category")


func test_load_item_returns_null_for_unknown_id() -> void:
	assert_eq(Crafting.load_item(&"no_such_item_exists"), null, "unknown id")


func test_craft_adds_the_output_item() -> void:
	var inventory := _stocked_inventory()
	var recipe: RecipeDef = load(RECIPE)

	var crafting := Crafting.new(recipe.station)
	assert_eq(crafting.craft(recipe, inventory), true, "craft succeeds")
	assert_eq(inventory.count(&"jade_pill"), 1, "output item was added")
	assert_eq(inventory.count(&"spirit_herb"), 0, "first input consumed")
	assert_eq(inventory.count(&"jade_ore"), 0, "second input consumed")


func test_craft_fails_when_output_is_undefined() -> void:
	var inventory := _stocked_inventory()
	# load() returns a cached shared resource; duplicate before mutating it or
	# every later test sees the broken outputs.
	var recipe: RecipeDef = load(RECIPE).duplicate()
	recipe.outputs = [&"not_a_real_item"]

	var crafting := Crafting.new(recipe.station)
	assert_eq(crafting.craft(recipe, inventory), false, "craft reports failure")
	assert_eq(inventory.count(&"not_a_real_item"), 0, "nothing added")


func test_craft_fails_without_every_input() -> void:
	var inventory := Inventory.new()
	inventory.add(load(HERB), 1)
	var recipe: RecipeDef = load(RECIPE)

	var crafting := Crafting.new(recipe.station)
	assert_eq(crafting.craft(recipe, inventory), false, "missing an input")
	assert_eq(inventory.count(&"jade_pill"), 0, "nothing added")
