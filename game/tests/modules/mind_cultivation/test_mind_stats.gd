extends TestCase

## ADR 0013: stat and resource id constants for the mind_cultivation module.


func test_resource_ids() -> void:
	assert_eq(String(MindStats.MIND_POWER), "mind_power", "mind_power id")
	assert_eq(String(MindStats.AWARENESS), "awareness", "awareness id")


func test_base_attribute_ids() -> void:
	assert_eq(String(MindStats.PERCEPTION), "perception", "perception id")
	assert_eq(String(MindStats.MENTAL_CLARITY), "mental_clarity", "mental_clarity id")


func test_derived_stat_ids() -> void:
	assert_eq(String(MindStats.MENTAL_ATTACK), "mental_attack", "mental_attack id")
	assert_eq(String(MindStats.MENTAL_DEFENSE), "mental_defense", "mental_defense id")
	assert_eq(
		String(MindStats.SPIRITUAL_SENSE_RANGE), "spiritual_sense_range", "spiritual_sense_range id"
	)
	assert_eq(String(MindStats.CRITICAL_CHANCE), "critical_chance", "critical_chance id")
	assert_eq(String(MindStats.DODGE_CHANCE), "dodge_chance", "dodge_chance id")
	assert_eq(
		String(MindStats.ILLUSION_RESISTANCE), "illusion_resistance", "illusion_resistance id"
	)
	assert_eq(
		String(MindStats.MIND_TECHNIQUE_POWER), "mind_technique_power", "mind_technique_power id"
	)
	assert_eq(
		String(MindStats.COMPREHENSION_BONUS), "comprehension_bonus", "comprehension_bonus id"
	)
