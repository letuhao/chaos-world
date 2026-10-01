extends TestCase

## ADR 0013: the mind_cultivation module contributes its stats through a StatProvider.


func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
				MindStats.MENTAL_CLARITY: 15.0,
			}
		)
	)
	MindCultivationApi.attach(actor)
	return actor


func test_attach_adds_resources() -> void:
	var actor := _actor_with_module()
	assert_eq(actor.resource(MindStats.MIND_POWER) != null, true, "mind_power pool")
	assert_eq(actor.resource(MindStats.AWARENESS) != null, true, "awareness pool")


func test_mental_attack_scales_with_perception() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(MindStats.MENTAL_ATTACK), 62.5, "mental attack")


func test_mental_defense_scales_with_clarity() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(MindStats.MENTAL_DEFENSE), 35.0, "mental defense")


func test_illusion_resistance_from_clarity_and_will() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(
		actor.stats.derived(MindStats.ILLUSION_RESISTANCE), 0.08, "illusion resistance"
	)


func test_mind_technique_power_scales() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER), 45.0, "technique power")


func test_comprehension_bonus_base() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(
		actor.stats.derived(MindStats.COMPREHENSION_BONUS), 1.12, "comprehension bonus"
	)


func test_meridian_strengthening_boosts_technique_power() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	var base_power := (20.0 * 1.5 + 15.0 * 1.0) * 1.0
	var expected := base_power * 1.05
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		expected,
		"meridian boosts technique power"
	)


func test_meridian_strengthening_boosts_mental_defense() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	var base_defense := (15.0 * 2.0 + 10.0 * 0.5) * 1.0
	var expected := base_defense * 1.05
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE), expected, "meridian boosts mental defense"
	)


func test_no_meridian_bonus_without_strengthening() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER), 45.0, "no meridian bonus")
