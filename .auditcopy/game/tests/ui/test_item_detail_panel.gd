extends TestCase

## The detail panel is the readable projection of one inventory row: identity,
## grade, rarity, realm requirement, fixed options, rolled affixes with their
## effective bound ranges, and what using the item would do. Headless tests
## assert `summary()`, never pixels.

const PANEL_SCENE := "res://src/ui/panels/item_detail_panel.tscn"
const RARITY := &"rare"


## Deterministic generator stream for a test fixture, so a realized roll is
## reproducible without depending on the global RNG.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _panel() -> ItemDetailPanel:
	var panel: ItemDetailPanel = load(PANEL_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	return panel


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


func _potion() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"minor_draught"
	def.display_name = "Minor Draught"
	def.category = ItemCategory.CONSUMABLE
	def.subcategory = ItemSubtype.PILL
	def.grade = ItemGrade.MORTAL
	def.stackable = true
	def.rarity = &"common"
	def.realm = &"qi_refining"
	def.roll_spec = {"count": 1, "contexts": ["base"]}
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	return def


func _entry(def: ItemDef, rolled: Array = [], slot: String = "") -> Dictionary:
	return {
		"def": def,
		"quantity": 1,
		"instance_id": "azure_blade_1",
		"display_name": def.display_name,
		"rarity": def.rarity,
		"realm": def.realm,
		"subtype": def.subcategory,
		"rolled": rolled,
		"durability": 0.75,
		"refinement": 2,
		"bound_to": "",
		"slot": slot,
	}


# --- Identity --------------------------------------------------------------


func test_identity_is_surfaced_for_the_selection() -> void:
	var panel := _panel()
	panel.show_entry(_entry(_blade()))
	var view := panel.summary()
	assert_eq(view["has_selection"], true, "a selection is shown")
	assert_eq(view["def_id"], "azure_blade", "definition id")
	assert_eq(view["display_name"], "Azure Blade", "display name")
	assert_eq(view["category"], "equipment", "category")
	assert_eq(view["subtype"], "weapon", "subtype")
	assert_eq(view["grade"], "mortal", "grade")
	assert_eq(view["rarity"], "rare", "rarity")
	assert_eq(view["rarity_label"], "Rare", "rarity readably named")
	assert_eq(view["realm"], "qi_refining", "realm requirement")
	assert_eq(view["required_tier"], 1, "required tier derived from the grade")
	assert_eq(view["activation"], "equipped", "activation channel")
	assert_eq(view["durability"], 0.75, "instance durability")
	assert_eq(view["refinement"], 2, "instance refinement")
	panel.free()


func test_the_equipped_slot_is_surfaced() -> void:
	var panel := _panel()
	panel.show_entry(_entry(_blade(), [], "weapon"))
	assert_eq(panel.summary()["equipped_slot"], "weapon", "slot reported")
	panel.free()


func test_clearing_resets_the_snapshot() -> void:
	var panel := _panel()
	panel.show_entry(_entry(_blade(), ItemGenerator.generate(_blade(), &"a", _rng(3)).rolled))
	assert_eq(panel.summary()["effect_line_count"] > 0, true, "something was shown")
	panel.clear()
	var view := panel.summary()
	assert_eq(view["has_selection"], false, "no selection")
	assert_eq(view["effect_line_count"], 0, "no effect rows")
	assert_eq(view["display_name"], "", "no name")
	panel.free()


# --- Fixed and rolled rows -------------------------------------------------


func test_fixed_options_and_rolled_affixes_are_both_shown() -> void:
	var panel := _panel()
	var def := _blade()
	var rolled := ItemGenerator.generate(def, &"azure_blade_1", _rng(7)).rolled
	panel.show_entry(_entry(def, rolled))
	var view := panel.summary()
	assert_eq(view["fixed_count"], 1, "the one fixed option is shown")
	assert_eq(view["rolled_count"], rolled.size(), "every rolled affix is shown")
	assert_eq(view["effect_line_count"], 1 + rolled.size(), "effect rows add up")
	var fixed_lines: Array = view["fixed_lines"]
	var rolled_lines: Array = view["rolled_lines"]
	assert_eq(fixed_lines.size(), 1, "one fixed line")
	assert_eq(rolled_lines.size(), rolled.size(), "one line per affix")
	panel.free()


func test_fixed_options_carry_their_value() -> void:
	var panel := _panel()
	panel.show_entry(_entry(_blade()))
	var lines: Array = panel.summary()["fixed_lines"]
	assert_eq(lines.size(), 1, "one fixed line")
	assert_ne(String(lines[0]).find("6.00"), -1, "the authored value is readable")
	panel.free()


func test_rolled_affixes_carry_their_value_and_effective_bound_range() -> void:
	var panel := _panel()
	var def := _blade()
	var rolled := ItemGenerator.generate(def, &"azure_blade_1", _rng(11)).rolled
	panel.show_entry(_entry(def, rolled))
	var lines: Array = panel.summary()["rolled_lines"]
	assert_eq(lines.size(), rolled.size(), "one line per affix")
	for index in lines.size():
		var line := String(lines[index])
		var effect: Dictionary = rolled[index]
		assert_ne(line.find("%.2f" % float(effect["value"])), -1, "realized value is readable")
		assert_ne(line.find("("), -1, "an effective range is shown for %s" % effect["option_id"])
		assert_ne(line.find(" - "), -1, "the range is bounded")
	panel.free()


func test_an_item_without_fixed_options_reports_none() -> void:
	var panel := _panel()
	var def := _blade()
	def.fixed_modifiers = []
	panel.show_entry(_entry(def, ItemGenerator.generate(def, &"azure_blade_1", _rng(5)).rolled))
	assert_eq(panel.summary()["fixed_count"], 0, "no fixed rows")
	assert_eq(panel.summary()["rolled_count"] > 0, true, "the rolls are still shown")
	panel.free()


# --- Preview ---------------------------------------------------------------


func test_a_consumable_reports_what_using_it_would_restore() -> void:
	var panel := _panel()
	panel.show_entry(_entry(_potion()))
	var view := panel.summary()
	assert_eq(view["activation"], "consumed", "consumed channel")
	var restores: Dictionary = view["restores"]
	assert_almost_eq(float(restores.get("health", 0.0)), 20.0, "the restoration is reported")
	assert_eq(view["properties"].size(), 0, "no item properties on this potion")
	panel.free()


func test_summary_keys_are_plain_strings() -> void:
	var panel := _panel()
	panel.show_entry(
		_entry(_blade(), ItemGenerator.generate(_blade(), &"azure_blade_1", _rng(2)).rolled)
	)
	for key in panel.summary().keys():
		assert_eq(typeof(key) == TYPE_STRING, true, "summary keys are plain strings")
	panel.free()
