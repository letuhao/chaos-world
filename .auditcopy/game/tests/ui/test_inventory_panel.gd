extends TestCase

## The inventory listing is a read-only projection of `ItemsApi.inventory`: one
## row per stackable batch, one row per distinct instance, and it follows the
## inventory's `changed` signal instead of polling.

const PANEL_SCENE := "res://src/ui/panels/inventory_panel.tscn"


func _panel() -> InventoryPanel:
	var panel: InventoryPanel = load(PANEL_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	return panel


func _actor() -> Actor:
	var actor := Actor.new(&"inventory_hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, 12)
	return actor


func _potion() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"minor_draught"
	def.display_name = "Minor Draught"
	def.category = ItemCategory.CONSUMABLE
	def.subcategory = ItemSubtype.PILL
	def.stackable = true
	def.max_stack = 20
	def.rarity = &"common"
	def.realm = &"qi_refining"
	return def


func _blade() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"azure_blade"
	def.display_name = "Azure Blade"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.WEAPON
	def.stackable = false
	def.rarity = &"rare"
	def.realm = &"qi_refining"
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 6.0}]
	return def


# --- Listing ---------------------------------------------------------------


func test_listing_reflects_the_facade_inventory() -> void:
	var actor := _actor()
	var panel := _panel()
	ItemsApi.inventory(actor).add(_potion(), 3)
	ItemsApi.inventory(actor).add(_blade(), 2)
	panel.bind(actor)
	var view := panel.summary()
	var inventory := ItemsApi.inventory(actor)
	assert_eq(
		view["rows"], inventory.stacks().size() + inventory.instances().size(), "one row per entry"
	)
	assert_eq(view["stacks"], 1, "one stackable batch")
	assert_eq(view["instances"], 2, "two distinct instances")
	assert_eq(view["used"], inventory.used_slots(), "slot usage comes from the facade")
	assert_eq(view["capacity"], 12, "capacity comes from the facade")
	assert_eq(view["empty"], false, "not empty")
	assert_eq(
		view["row_def_ids"],
		["minor_draught", "azure_blade", "azure_blade"],
		"rows in inventory order"
	)
	panel.free()


func test_distinct_realizations_of_one_definition_list_as_separate_rows() -> void:
	var actor := _actor()
	var panel := _panel()
	var potion := _potion()
	potion.rarity = &"rare"
	potion.roll_spec = {"count": 2, "contexts": ["prefix", "postfix"]}
	var inventory := ItemsApi.inventory(actor)
	# Two hand-authored realizations of the same definition: they must stay
	# separately selectable instead of collapsing onto one row.
	var first := ItemInstance.new(&"minor_draught", &"a")
	first.rolled = [{"option_id": &"restore_qi", "op": &"FLAT", "scope": &"current", "value": 10.0}]
	var second := ItemInstance.new(&"minor_draught", &"b")
	second.rolled = [
		{"option_id": &"restore_qi", "op": &"FLAT", "scope": &"current", "value": 11.0}
	]
	inventory.add_batch(ItemStack.from_instance(first, 2))
	inventory.add_batch(ItemStack.from_instance(second, 3))
	panel.bind(actor)
	var view := panel.summary()
	assert_eq(view["rows"], 2, "one row per realization")
	assert_eq(view["stacks"], 2, "both are stackable batches")
	var keys: Array = view["row_keys"]
	assert_ne(keys[0], keys[1], "the two rows are separately addressable")
	panel.free()


func test_an_empty_inventory_reports_no_rows() -> void:
	var actor := _actor()
	var panel := _panel()
	panel.bind(actor)
	var view := panel.summary()
	assert_eq(view["rows"], 0, "no rows")
	assert_eq(view["empty"], true, "empty")
	assert_eq(view["has_selection"], false, "nothing selected")
	assert_eq(view["selected_key"], "", "no selection key")
	panel.free()


# --- Selection -------------------------------------------------------------


func test_selection_reports_the_selected_row() -> void:
	var actor := _actor()
	var panel := _panel()
	ItemsApi.inventory(actor).add(_potion(), 4)
	ItemsApi.inventory(actor).add(_blade(), 1)
	panel.bind(actor)
	var keys: Array = panel.summary()["row_keys"]
	panel.select_key(String(keys[1]))
	var view := panel.summary()
	assert_eq(view["has_selection"], true, "something is selected")
	assert_eq(view["selected_def_id"], "azure_blade", "the instance row is selected")
	assert_eq(view["selected_kind"], "instance", "kind is reported")
	assert_eq(view["selected_quantity"], 1, "an instance counts as one")
	assert_eq(view["selected_key"], String(keys[1]), "the selection key matches")
	panel.select_key(String(keys[0]))
	assert_eq(panel.summary()["selected_def_id"], "minor_draught", "selection moved to the batch")
	assert_eq(panel.summary()["selected_quantity"], 4, "batch quantity is reported")
	panel.free()


func test_selection_falls_back_to_the_first_row_when_the_selection_is_gone() -> void:
	var actor := _actor()
	var panel := _panel()
	ItemsApi.inventory(actor).add(_potion(), 1)
	panel.bind(actor)
	panel.summary()
	ItemsApi.consume_item(actor, &"minor_draught")
	assert_eq(panel.summary()["rows"], 0, "the row is gone")
	assert_eq(panel.summary()["has_selection"], false, "nothing is left selected")
	panel.free()


# --- Signal driven ---------------------------------------------------------


func test_listing_follows_the_inventory_changed_signal() -> void:
	var actor := _actor()
	var panel := _panel()
	panel.bind(actor)
	assert_eq(panel.summary()["rows"], 0, "starts empty")
	# No refresh() call: the facade's own `changed` signal has to drive the view.
	ItemsApi.inventory(actor).add(_potion(), 2)
	assert_eq(panel.summary()["rows"], 1, "the new batch showed up on its own")
	assert_eq(panel.summary()["used"], 1, "slot usage followed")
	ItemsApi.inventory(actor).add(_blade(), 1)
	assert_eq(panel.summary()["rows"], 2, "the new instance showed up on its own")
	panel.free()


func test_summary_never_leaks_object_references() -> void:
	var actor := _actor()
	var panel := _panel()
	ItemsApi.inventory(actor).add(_blade(), 1)
	panel.bind(actor)
	for key in panel.summary().keys():
		assert_eq(typeof(key) == TYPE_STRING, true, "summary keys are plain strings")
	for key in ["rows", "capacity", "selected_def_id"]:
		assert_eq(
			typeof(panel.summary()[key]) in [TYPE_INT, TYPE_STRING, TYPE_BOOL, TYPE_FLOAT],
			true,
			"%s is a primitive" % key
		)
	panel.free()
