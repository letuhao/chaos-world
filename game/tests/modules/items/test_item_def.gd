extends TestCase

## ADR 0025/0028: option-backed item definitions, grades and instance state.
## Fixed modifiers reference master option ids; the legacy raw stat maps are gone.


func test_grade_maps_to_realm_tier() -> void:
	assert_eq(ItemGrade.required_tier(ItemGrade.MORTAL), 1, "mortal tier 1")
	assert_eq(ItemGrade.required_tier(ItemGrade.HEAVEN), 3, "heaven tier 3")
	assert_eq(ItemGrade.required_tier(ItemGrade.DIVINE), 4, "divine tier 4")
	assert_eq(ItemGrade.required_tier(&"unknown"), 1, "unknown defaults")


func test_subtype_vocabulary() -> void:
	assert_eq(ItemSubtype.HERB, &"herb", "herb")
	assert_eq(ItemSubtype.PILL, &"pill", "pill")
	assert_eq(ItemSubtype.ARTIFACT, &"artifact", "artifact")


func test_category_resolves_an_activation_with_a_consumer() -> void:
	var def := ItemDef.new()
	def.category = ItemCategory.EQUIPMENT
	assert_eq(def.activation(), ItemActivation.EQUIPPED, "equipment equips")
	def.category = ItemCategory.CONSUMABLE
	assert_eq(def.activation(), ItemActivation.CONSUMED, "consumable is consumed")
	def.category = ItemCategory.TECHNIQUE
	assert_eq(def.activation(), ItemActivation.LEARNED, "technique is learned")
	def.category = ItemCategory.MATERIAL
	assert_eq(def.activation(), ItemActivation.CRAFTED, "material is crafted")
	def.category = ItemCategory.KEY
	assert_eq(def.activation(), ItemActivation.PROPERTY, "key is a property item")


func test_fixed_modifiers_resolve_through_the_master_catalog() -> void:
	var def := ItemDef.new()
	def.id = &"ring"
	def.category = ItemCategory.EQUIPMENT
	def.fixed_modifiers = [{"option_id": &"core_max_health", "value": 12.0}]
	var effects := def.effects()
	assert_eq(effects.size(), 1, "one effect")
	assert_eq(effects[0].get("option_id"), &"core_max_health", "option id")
	assert_eq(effects[0].get("target_id"), Stat.MAX_HEALTH, "target from the catalog")
	assert_eq(effects[0].get("channel"), &"fixed", "fixed channel")
	assert_eq(effects[0].get("value"), 12.0, "authored fixed value preserved")


func test_unknown_fixed_option_is_ignored_not_invented() -> void:
	var def := ItemDef.new()
	def.id = &"ring"
	def.category = ItemCategory.EQUIPMENT
	def.fixed_modifiers = [{"option_id": &"not_a_registered_option", "value": 5.0}]
	assert_eq(def.effects().size(), 0, "unregistered option resolves to nothing")


func test_fixed_option_from_another_activation_is_rejected() -> void:
	# A resource-restore option may not be authored on equipment: equipment only
	# activates through `equipped`, so the option has no consumer there.
	var def := ItemDef.new()
	def.id = &"sword"
	def.category = ItemCategory.EQUIPMENT
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 5.0}]
	assert_eq(def.effects().size(), 0, "cross-activation option dropped")


func test_stat_modifiers_are_source_tagged() -> void:
	var def := ItemDef.new()
	def.id = &"ring"
	def.category = ItemCategory.EQUIPMENT
	def.fixed_modifiers = [{"option_id": &"core_max_health", "value": 12.0}]
	var modifiers := ItemEffects.stat_modifiers(def.effects(), &"ring_1")
	assert_eq(modifiers.size(), 1, "one modifier")
	assert_eq(modifiers[0].stat, Stat.MAX_HEALTH, "target stat")
	assert_eq(modifiers[0].source, &"ring_1", "source tagged")


func test_instance_round_trip_preserves_realized_rolls() -> void:
	var instance := ItemInstance.new(&"sword", &"sword_1")
	instance.refinement = 3
	instance.rarity = &"rare"
	instance.realm = &"spirit_sea"
	instance.catalog_version = 2
	instance.rolled = [
		{
			"option_id": &"core_crit_chance",
			"target_type": &"stat",
			"target_id": &"crit_chance",
			"scope": &"",
			"op": &"PERCENT",
			"unit": &"rate",
			"value": 0.12,
			"channel": &"rolled",
		}
	]
	var restored := ItemInstance.from_dict(instance.to_dict())
	assert_eq(restored.refinement, 3, "refinement")
	assert_eq(restored.rarity, &"rare", "rarity")
	assert_eq(restored.realm, &"spirit_sea", "realm")
	assert_eq(restored.rolled.size(), 1, "realized roll kept")
	assert_almost_eq(float(restored.rolled[0]["value"]), 0.12, "realized value kept")
	assert_eq(restored.catalog_version, 2, "provenance kept")


func test_legacy_payload_migrates_without_inventing_rolls() -> void:
	var legacy := {
		"def_id": "sword",
		"instance_id": "sword_1",
		"durability": 0.5,
		"refinement": 2,
		"affixes": ["sharp"],
		"bound_to": "",
	}
	var migrated := ItemInstance.migrate(legacy)
	var instance := ItemInstance.from_dict(migrated)
	assert_eq(instance.refinement, 2, "identity preserved")
	assert_eq(instance.durability, 0.5, "durability preserved")
	assert_eq(instance.rolled.size(), 0, "no invented rolls")
	assert_eq(instance.rarity, &"common", "conservative rarity")


func test_stacking_signature_separates_different_rolls() -> void:
	var a := ItemInstance.new(&"potion", &"a")
	a.rolled = [{"option_id": &"restore_health", "op": &"FLAT", "value": 10.0}]
	var b := ItemInstance.new(&"potion", &"b")
	b.rolled = [{"option_id": &"restore_health", "op": &"FLAT", "value": 11.0}]
	var c := ItemInstance.new(&"potion", &"c")
	c.rolled = [{"option_id": &"restore_health", "op": &"FLAT", "value": 10.0}]
	assert_eq(a.signature_matches(b), false, "different rolls do not merge")
	assert_eq(a.signature_matches(c), true, "identical rolls merge")


func test_stack_round_trip() -> void:
	var stack := ItemStack.from_dict(ItemStack.new(&"herb", 7).to_dict())
	assert_eq(stack.def_id, &"herb", "stack def")
	assert_eq(stack.quantity, 7, "stack qty")
