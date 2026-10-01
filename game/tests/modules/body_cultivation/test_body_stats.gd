extends TestCase

## ADR 0012: body cultivation stat and resource id constants.


func test_base_attribute_ids() -> void:
	assert_eq(BodyStats.BONE_DENSITY, &"bone_density", "bone_density id")
	assert_eq(BodyStats.MUSCLE_FIBER, &"muscle_fiber", "muscle_fiber id")
	assert_eq(BodyStats.ORGAN_VITALITY, &"organ_vitality", "organ_vitality id")


func test_derived_stat_ids() -> void:
	assert_eq(BodyStats.PHYSICAL_ATTACK, &"physical_attack", "physical_attack id")
	assert_eq(BodyStats.PHYSICAL_DEFENSE, &"physical_defense", "physical_defense id")
	assert_eq(BodyStats.MOVE_SPEED, &"move_speed", "move_speed id")
	assert_eq(BodyStats.CARRY_CAPACITY, &"carry_capacity", "carry_capacity id")
	assert_eq(BodyStats.REGENERATION, &"regeneration", "regeneration id")
	assert_eq(BodyStats.POISE, &"poise", "poise id")
	assert_eq(BodyStats.BODY_CULTIVATION_POWER, &"body_cultivation_power", "power id")


func test_resource_ids() -> void:
	assert_eq(BodyStats.BODY_INTEGRITY, &"body_integrity", "body_integrity id")
