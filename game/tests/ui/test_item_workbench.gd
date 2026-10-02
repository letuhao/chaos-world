extends TestCase

## The workbench screen wires the three panels to the `items` facade. These
## tests assert `summary()` and the screen's actions, never pixels — including
## that a rejected action leaves the actor untouched and names the gameplay
## reason.

const SCENE := "res://src/ui/screens/item_workbench.tscn"
const RARITY := &"rare"


## Deterministic generator stream for a test fixture, so a realized roll is
## reproducible without depending on the global RNG.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _screen() -> ItemWorkbench:
	var screen: ItemWorkbench = load(SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


func _actor() -> Actor:
	var actor := Actor.new(&"workbench_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	ItemsApi.attach(actor, 12)
	return actor


func _potion() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"minor_draught"
	def.display_name = "Minor Draught"
	def.category = ItemCategory.CONSUMABLE
	def.subcategory = ItemSubtype.PILL
	def.grade = ItemGrade.MORTAL
	def.stackable = true
	def.max_stack = 20
	def.rarity = &"common"
	def.realm = &"qi_refining"
	def.roll_spec = {"count": 1, "contexts": ["base"]}
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	return def


## A consumable with no authored option: the facade has nothing to apply, so
## using it is always rejected for a gameplay reason rather than a UI one.
func _blank_charm() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"blank_charm"
	def.display_name = "Blank Charm"
	def.category = ItemCategory.CONSUMABLE
	def.subcategory = ItemSubtype.TALISMAN
	def.grade = ItemGrade.MORTAL
	def.stackable = true
	def.rarity = &"common"
	def.realm = &"qi_refining"
	def.roll_spec = {"count": 1, "contexts": ["base"]}
	return def


func _blade() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"azure_blade"
	def.display_name = "Azure Blade"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.WEAPON
	def.grade = ItemGrade.MORTAL
	def.stackable = false
	def.rarity = RARITY
	def.realm = &"qi_refining"
	def.roll_spec = {"count": ItemRarity.affix_count(RARITY), "contexts": ["prefix", "postfix"]}
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 6.0}]
	return def


func _enabled(screen: ItemWorkbench, action: String) -> bool:
	var flags: Dictionary = screen.summary()["action_enabled"]
	return bool(flags[action])


# --- Read model ------------------------------------------------------------


func test_the_app_owned_scene_mounts_the_same_screen() -> void:
	var mounted: ItemWorkbench = (
		load("res://scenes/item_workbench/item_workbench.tscn").instantiate()
	)
	(Engine.get_main_loop() as SceneTree).root.add_child(mounted)
	# Unbound, the screen reports `{}` per the UI standard; binding an actor is
	# what makes the summary a readable contract again.
	assert_eq(mounted.summary(), {}, "an unbound screen reports an empty summary")
	mounted.setup(_actor())
	assert_eq(mounted.summary()["has_actor"], true, "and it takes an actor")
	mounted.free()


func test_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	# The UI standard: `summary()` is `{}` when no actor is bound, so a test never
	# reads a half-initialised screen's keys. That includes `action_enabled`:
	# with nothing selected there is no state to report, and zeroed flags would
	# invite a caller to read a screen that was never set up.
	assert_eq(screen.summary(), {}, "no actor means an empty summary, not zeroed keys")
	screen.setup(_actor())
	# The flags exist once an actor is bound, and an empty inventory leaves every
	# action off — the honest way to say "nothing here to act on".
	assert_eq(screen.summary()["has_actor"], true, "an actor publishes the contract")
	assert_eq(_enabled(screen, "use"), false, "use is off")
	assert_eq(_enabled(screen, "generate"), false, "generate is off")
	screen.free()


func test_the_listing_and_the_detail_follow_the_facade_inventory() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_potion(), 3)
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	assert_eq(view["has_actor"], true, "actor bound")
	assert_eq(view["actor_id"], "workbench_hero", "actor reported")
	assert_eq(view["row_count"], 2, "one row per inventory entry")
	assert_ne(view["selection_key"], "", "a row is selected")
	assert_eq(bool(view["detail"]["has_selection"]), true, "the detail shows it")
	screen.free()


func test_the_screen_follows_the_inventory_signal_without_polling() -> void:
	var actor := _actor()
	var screen := _screen()
	screen.setup(actor)
	assert_eq(screen.summary()["row_count"], 0, "starts empty")
	# No refresh() call: the facade's own `changed` signal has to drive the view.
	ItemsApi.inventory(actor).add(_blade(), 1)
	assert_eq(screen.summary()["row_count"], 1, "the new instance showed up on its own")
	ItemsApi.inventory(actor).add(_potion(), 2)
	assert_eq(screen.summary()["row_count"], 2, "the new batch showed up on its own")
	screen.free()


func test_the_detail_shows_fixed_and_rolled_rows_for_the_selection() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	assert_eq(int(view["fixed_count"]), 1, "the fixed option is shown")
	assert_eq(int(view["rolled_count"]) > 0, true, "the rolled affixes are shown")
	assert_eq(
		int(view["effect_line_count"]),
		int(view["fixed_count"]) + int(view["rolled_count"]),
		"every effect row is counted"
	)
	assert_eq(String(view["detail"]["rarity_label"]), "Rare", "rarity readably named")
	assert_eq(String(view["detail"]["grade"]), "mortal", "grade shown")
	assert_eq(String(view["detail"]["realm"]), "qi_refining", "realm requirement shown")
	screen.free()


func test_action_state_follows_the_selection() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_potion(), 2)
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	var keys: Array = screen.summary()["inventory"]["row_keys"]
	screen.select_key(String(keys[0]))
	assert_eq(_enabled(screen, "use"), true, "a consumable is usable")
	assert_eq(_enabled(screen, "equip"), false, "a consumable is not equippable")
	assert_eq(_enabled(screen, "generate"), true, "anything can be generated from")
	screen.select_key(String(keys[1]))
	assert_eq(_enabled(screen, "equip"), true, "equipment is equippable")
	assert_eq(_enabled(screen, "use"), false, "equipment is not usable")
	assert_eq(_enabled(screen, "unequip"), false, "no slot is filled yet")
	screen.free()


# --- Actions ---------------------------------------------------------------


func test_use_consumes_one_unit_and_reports_success() -> void:
	var actor := _actor()
	actor.resource(&"health").change(-50.0)
	ItemsApi.inventory(actor).add(_potion(), 3)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(screen.act_use(), true, "used")
	assert_almost_eq(actor.resource(&"health").current, 70.0, "one restoration applied")
	assert_eq(ItemsApi.inventory(actor).count(&"minor_draught"), 2, "one consumed")
	assert_eq(screen.summary()["tone"], "ok", "reported as accepted")
	screen.free()


func test_equip_and_unequip_round_trip_through_the_facade() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(screen.act_equip(), true, "equipped")
	var equipment := ItemsApi.equipment(actor)
	assert_ne(equipment.definition(&"weapon"), null, "the blade is in the weapon slot")
	assert_eq(ItemsApi.has_item(actor, &"azure_blade"), false, "no longer carried")
	assert_eq(screen.act_unequip(), true, "unequipped")
	assert_eq(equipment.definition(&"weapon"), null, "the slot is empty again")
	assert_eq(ItemsApi.has_item(actor, &"azure_blade"), true, "carried again")
	screen.free()


func test_generate_adds_a_fresh_realization() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	var before := ItemsApi.inventory(actor).instances().size()
	assert_eq(screen.act_generate(), true, "generated")
	assert_eq(ItemsApi.inventory(actor).instances().size(), before + 1, "one more instance")
	assert_eq(screen.act_generate(), true, "generated again")
	assert_eq(ItemsApi.inventory(actor).instances().size(), before + 2, "and another")
	var ids: Array = []
	for instance in ItemsApi.inventory(actor).instances():
		ids.append(String(instance.instance_id))
	var unique := {}
	for instance_id in ids:
		unique[instance_id] = true
	assert_eq(ids.size(), before + 2, "one more instance per generation")
	assert_eq(unique.size(), ids.size(), "every held instance keeps its own identity")
	screen.free()


# --- Rejections ------------------------------------------------------------


func test_a_use_with_no_applicable_effect_changes_nothing_and_names_the_reason() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_blank_charm(), 2)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(screen.act_use(), false, "rejected")
	var view := screen.summary()
	assert_eq(String(view["message"]), "Rejected: no_applicable_effect", "the gameplay reason")
	assert_eq(String(view["tone"]), "error", "reported as a rejection")
	assert_eq(ItemsApi.inventory(actor).count(&"blank_charm"), 2, "nothing consumed")
	assert_eq(int(view["row_count"]), 1, "the row is still listed")
	assert_eq(bool(view["detail"]["has_selection"]), true, "the detail still shows it")
	screen.free()


func test_equipping_a_non_equippable_item_changes_nothing_and_names_the_reason() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_potion(), 2)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(_enabled(screen, "equip"), false, "the action is offered as disabled")
	assert_eq(screen.act_equip(), false, "rejected")
	var view := screen.summary()
	assert_eq(String(view["message"]), "Rejected: not_equipment", "the gameplay reason")
	assert_eq(String(view["tone"]), "error", "reported as a rejection")
	assert_eq(ItemsApi.inventory(actor).count(&"minor_draught"), 2, "nothing consumed")
	assert_eq(ItemsApi.equipment(actor).all().size(), 0, "nothing equipped")
	screen.free()


func test_unequipping_an_empty_slot_changes_nothing_and_names_the_reason() -> void:
	var actor := _actor()
	ItemsApi.inventory(actor).add(_blade(), 1)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(_enabled(screen, "unequip"), false, "no slot is filled")
	assert_eq(screen.act_unequip(), false, "rejected")
	var view := screen.summary()
	assert_eq(String(view["message"]), "Rejected: slot_empty", "the gameplay reason")
	assert_eq(String(view["tone"]), "error", "reported as a rejection")
	assert_eq(ItemsApi.has_item(actor, &"azure_blade"), true, "still carried")
	screen.free()


func test_unequipping_into_a_full_inventory_changes_nothing_and_names_the_reason() -> void:
	var actor := _actor()
	ItemsApi.attach(actor, 2)
	ItemsApi.inventory(actor).add(_blade(), 1)
	ItemsApi.inventory(actor).add(_potion(), 1)
	var screen := _screen()
	screen.setup(actor)
	var keys: Array = screen.summary()["inventory"]["row_keys"]
	screen.select_key(String(keys[1]))
	assert_eq(_enabled(screen, "equip"), true, "the blade is equippable")
	assert_eq(screen.act_equip(), true, "equipped into the freed slot")
	assert_eq(ItemsApi.inventory(actor).is_full(), false, "the freed slot is available")
	ItemsApi.inventory(actor).add(_blade(), 1)
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "the inventory refilled")
	assert_eq(screen.act_unequip(), false, "rejected")
	var view := screen.summary()
	assert_eq(String(view["message"]), "Rejected: inventory_full", "the gameplay reason")
	assert_ne(ItemsApi.equipment(actor).definition(&"weapon"), null, "still equipped")
	screen.free()


func test_an_item_bound_to_someone_else_is_rejected_with_a_reason() -> void:
	var actor := _actor()
	var def := _blade()
	var instance := ItemGenerator.generate(def, &"stolen_blade", _rng(4))
	instance.def_ref = def
	instance.bound_to = &"other_hero"
	ItemsApi.inventory(actor).add_instance(instance)
	var screen := _screen()
	screen.setup(actor)
	assert_eq(_enabled(screen, "equip"), false, "the action is offered as disabled")
	assert_eq(screen.act_equip(), false, "rejected")
	var view := screen.summary()
	assert_eq(String(view["message"]), "Rejected: bound_to_other", "the gameplay reason")
	assert_eq(ItemsApi.equipment(actor).all().size(), 0, "nothing equipped")
	assert_eq(ItemsApi.has_item(actor, &"azure_blade"), true, "still carried")
	assert_eq(String(view["detail"]["bound_to"]), "other_hero", "the binding is shown")
	screen.free()
