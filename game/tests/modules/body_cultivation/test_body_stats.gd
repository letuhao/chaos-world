extends TestCase

## ADR 0012: body cultivation stat and resource id constants.


func test_base_attribute_ids() -> void:
	assert_eq(BodyStats.BONE_DENSITY, &"bone_density", "bone_density id")
	assert_eq(BodyStats.MUSCLE_FIBER, &"muscle_fiber", "muscle_fiber id")
	assert_eq(BodyStats.ORGAN_VITALITY, &"organ_vitality", "organ_vitality id")


## Attack, defense, move speed, and poise are CORE stats. The body module
## aliases them rather than inventing private ids: a provider value replaces the
## core baseline for whatever id it emits (ADR 0026), so a private id would
## contribute nothing a player or another system could read.
func test_core_owned_stat_ids_are_aliased_not_duplicated() -> void:
	assert_eq(BodyStats.PHYSICAL_ATTACK, Stat.ATTACK_PHYSICAL, "attack aliases core")
	assert_eq(BodyStats.PHYSICAL_DEFENSE, Stat.DEFENSE_PHYSICAL, "defense aliases core")
	assert_eq(BodyStats.MOVE_SPEED, Stat.MOVE_SPEED, "move speed aliases core")
	assert_eq(BodyStats.POISE, Stat.POISE, "poise aliases core")


func test_module_owned_stat_ids_are_unique_to_body() -> void:
	assert_eq(BodyStats.CARRY_CAPACITY, &"carry_capacity", "carry_capacity id")
	assert_eq(BodyStats.REGENERATION, &"regeneration", "regeneration id")
	assert_eq(BodyStats.BODY_CULTIVATION_POWER, &"body_cultivation_power", "power id")
	assert_eq(BodyStats.ACUPOINT_QUALITY, &"acupoint_quality", "acupoint quality id")
	assert_eq(BodyStats.ACUPOINT_COUNT, &"acupoint_count", "acupoint count id")
	assert_eq(BodyStats.ACUPOINT_BLOCKED_COUNT, &"acupoint_blocked_count", "blocked count id")


func test_resource_ids() -> void:
	assert_eq(BodyStats.BODY_INTEGRITY, &"body_integrity", "body_integrity id")
