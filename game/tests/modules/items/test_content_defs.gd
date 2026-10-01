extends TestCase

## ADR 0008: example content defs load and carry their acquisition links.


func test_item_def_loads_with_sources() -> void:
	var def := load("res://data/items/material/spirit_herb.tres")
	assert_eq(def is ItemDef, true, "loads ItemDef")
	assert_eq(def.id, &"spirit_herb", "id")
	assert_eq(def.category, ItemCategory.MATERIAL, "category")
	assert_eq(def.sources.has(&"gather"), true, "gather source")


func test_recipe_def_loads() -> void:
	var recipe := load("res://data/recipes/jade_pill_recipe.tres")
	assert_eq(recipe is RecipeDef, true, "loads RecipeDef")
	assert_eq(recipe.outputs.has(&"jade_pill"), true, "output")
	assert_eq(recipe.inputs.has(&"spirit_herb"), true, "input")


func test_craft_item_links_to_recipe() -> void:
	var pill := load("res://data/items/consumable/jade_pill.tres")
	assert_eq(pill.sources.has(&"craft:jade_pill_recipe"), true, "craft source")
