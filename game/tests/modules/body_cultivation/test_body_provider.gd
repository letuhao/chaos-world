extends TestCase

## ADR 0012: body cultivation provider emits derived stats from base attributes,
## body integrity, and path rank.


func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"body_cultivator",
			{
				Stat.PHYSIQUE: 10.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	BodyCultivationApi.attach(actor)
	return actor


func test_physical_attack() -> void:
	var actor := _actor_with_module()
	# muscle_fiber * 2.0 + bone_density * 1.0 = 10*2 + 10*1 = 30
	# integrity_factor = 1.0 (full), multiplier = 1.0 (no path)
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 30.0, "physical attack")


func test_physical_defense() -> void:
	var actor := _actor_with_module()
	# bone_density * 1.5 + organ_vitality * 1.0 = 10*1.5 + 10*1 = 25
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_DEFENSE), 25.0, "physical defense")


func test_move_speed() -> void:
	var actor := _actor_with_module()
	# muscle_fiber * 0.5 = 10 * 0.5 = 5
	assert_almost_eq(actor.stats.derived(BodyStats.MOVE_SPEED), 5.0, "move speed")


func test_carry_capacity() -> void:
	var actor := _actor_with_module()
	# bone_density * 10.0 + muscle_fiber * 5.0 = 10*10 + 10*5 = 150
	assert_almost_eq(actor.stats.derived(BodyStats.CARRY_CAPACITY), 150.0, "carry capacity")


func test_regeneration() -> void:
	var actor := _actor_with_module()
	# organ_vitality * 0.3 = 10 * 0.3 = 3
	assert_almost_eq(actor.stats.derived(BodyStats.REGENERATION), 3.0, "regeneration")


func test_poise() -> void:
	var actor := _actor_with_module()
	# bone_density * 0.8 + physique * 0.5 = 10*0.8 + 10*0.5 = 13
	assert_almost_eq(actor.stats.derived(BodyStats.POISE), 13.0, "poise")


func test_body_cultivation_power() -> void:
	var actor := _actor_with_module()
	# (bone_density + muscle_fiber + organ_vitality) * 0.5 = 30 * 0.5 = 15
	assert_almost_eq(actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "power")


func test_integrity_affects_stats() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 30.0, "full integrity")
	actor.change_resource(BodyStats.BODY_INTEGRITY, -50.0)
	# integrity_ratio = 0.5, factor = 0.5 + 0.5*0.5 = 0.75
	# result = 30 * 0.75 * 1.0 = 22.5
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 22.5, "half integrity")


func test_realm_multiplier() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 30.0, "no path")
	# spirit_sea is index 10, tier 2 (Spirit), local index 2 (1-based).
	# P = 8 * 1.22^1 = 9.76, T = P^0.55 ≈ 3.501
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"spirit_sea"))
	# result = 30 * 1.0 * 3.501279 ≈ 105.03128
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 105.03128, "spirit sea")


func test_provider_retrievable() -> void:
	var actor := _actor_with_module()
	var provider := BodyCultivationApi.provider(actor)
	assert_eq(provider != null, true, "provider retrievable")
	assert_eq(provider is BodyProvider, true, "provider type")


func test_meridian_power_bonus_scales_stats() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	# Base physical_attack = 30.0
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 30.0, "no meridian bonus")
	# Expand and strengthen a meridian for power bonus
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	# power_bonus for lung = 0.05, so scaling = 1.0 * 1.0 * (1.0 + 0.05) = 1.05
	# physical_attack = 30.0 * 1.05 = 31.5
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 31.5, "meridian power bonus")


func test_meridian_power_bonus_scales_body_cultivation_power() -> void:
	var actor := _actor_with_module()
	actor.set_component(&"meridians", actor.meridians)
	# Base body_cultivation_power = 15.0
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "no meridian bonus"
	)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	# power_bonus = 0.05, scaling = 1.05
	# body_cultivation_power = 15.0 * 1.05 = 15.75
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.75, "meridian power on bcp"
	)


func test_no_meridian_component_gives_no_bonus() -> void:
	var actor := _actor_with_module()
	# No meridians component attached — should default to no bonus
	assert_almost_eq(actor.stats.derived(BodyStats.PHYSICAL_ATTACK), 30.0, "no meridian component")
