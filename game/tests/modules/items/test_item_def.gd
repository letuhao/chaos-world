extends TestCase

## ADR 0007: item defs, grades, and serialization.


func test_grade_maps_to_realm_tier() -> void:
	assert_eq(ItemGrade.required_tier(ItemGrade.MORTAL), 1, "mortal tier 1")
	assert_eq(ItemGrade.required_tier(ItemGrade.HEAVEN), 3, "heaven tier 3")
	assert_eq(ItemGrade.required_tier(ItemGrade.DIVINE), 4, "divine tier 4")
	assert_eq(ItemGrade.required_tier(&"unknown"), 1, "unknown defaults")


func test_subtype_vocabulary() -> void:
	assert_eq(ItemSubtype.HERB, &"herb", "herb")
	assert_eq(ItemSubtype.PILL, &"pill", "pill")
	assert_eq(ItemSubtype.ARTIFACT, &"artifact", "artifact")


func test_build_modifiers_is_source_tagged() -> void:
	var def := ItemDef.new()
	def.id = &"ring"
	def.percent_modifiers = {String(Stat.MAX_HEALTH): 0.2}
	var modifiers := def.build_modifiers(&"ring_1")
	assert_eq(modifiers.size(), 1, "one modifier")
	assert_eq(modifiers[0].source, &"ring_1", "source tagged")


func test_stack_and_instance_round_trip() -> void:
	var stack := ItemStack.from_dict(ItemStack.new(&"herb", 7).to_dict())
	assert_eq(stack.def_id, &"herb", "stack def")
	assert_eq(stack.quantity, 7, "stack qty")
	var instance := ItemInstance.new(&"sword", &"sword_1")
	instance.refinement = 3
	instance.affixes.append(&"sharp")
	var restored := ItemInstance.from_dict(instance.to_dict())
	assert_eq(restored.refinement, 3, "refinement")
	assert_eq(restored.affixes.has(&"sharp"), true, "affix")
