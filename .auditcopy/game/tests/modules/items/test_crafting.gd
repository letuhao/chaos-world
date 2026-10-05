extends TestCase

## Crafting must resolve an ItemDef by id. Items live at
## res://data/items/<category>/<id>.tres, so a lookup that omits <category> resolves
## nothing and craft() silently yields no output.

const RECIPE := "res://data/recipes/jade_pill_recipe.tres"
const HERB := "res://data/items/material/spirit_herb.tres"
const ORE := "res://data/items/material/jade_ore.tres"


func teardown() -> void:
	# The overlay stack is process-wide static state; reset it so no other suite
	# inherits this one's wiring.
	Crafting.set_overlay_roots([])


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


## The overlay pilot (ADR 0184 §5): with the base roots only, the merge must
## find exactly the ids the legacy scan finds — the byte-identical guarantee
## that lets a mod append or override without changing default behavior.


func test_overlay_merge_with_base_roots_matches_the_legacy_scan() -> void:
	Crafting.set_overlay_roots([])
	var merged := Crafting.overlay_merge()
	assert_eq(bool(merged.get("ok", false)), true, "the base stack merges")
	var merged_ids: Array[String] = []
	for entry in merged["merged"]:
		merged_ids.append(String(entry["id"]))
	var scanned_ids: Array[String] = []
	for root in Crafting.ITEM_ROOTS:
		for path in ContentScan.files_under(root):
			scanned_ids.append(path.get_file().trim_suffix(".tres"))
	merged_ids.sort()
	scanned_ids.sort()
	assert_eq(
		merged_ids, scanned_ids, "the overlay merge finds exactly the ids the legacy scan finds"
	)


func test_explicit_base_only_stack_merges_the_authored_items() -> void:
	var base_only: Array = []
	for root in Crafting.ITEM_ROOTS:
		base_only.append({"dir": root, "owner": "base", "declared_overrides": []})
	Crafting.set_overlay_roots(base_only)
	var merged := Crafting.overlay_merge()
	assert_eq(bool(merged.get("ok", false)), true, "an explicit base-only stack merges")
	assert_eq(int(merged["merged"].size()) > 0, true, "and finds the authored items")
	Crafting.set_overlay_roots([])


func test_resolve_overlay_agrees_with_resolve_on_real_items() -> void:
	Crafting.set_overlay_roots([])
	var via_overlay := Crafting.resolve_overlay(&"spirit_herb")
	assert_eq(via_overlay == null, false, "the overlay resolves a real item")
	if via_overlay == null:
		return
	assert_eq(via_overlay.id, &"spirit_herb", "with its id intact")
	assert_eq(Crafting.resolve(&"spirit_herb") == null, false, "the legacy scan resolves it too")
	assert_eq(Crafting.resolve_overlay(&"no_such_item_exists"), null, "an unknown id is null")
