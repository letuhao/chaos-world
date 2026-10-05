extends TestCase

## ADR 0011: QiProvider emits derived stats from base attributes and realm rank.


func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				QiStats.QI_AFFINITY: 20.0,
				QiStats.QI_CONTROL: 15.0,
				QiStats.DANTIAN_CAPACITY: 30.0,
			}
		)
	)
	QiCultivationApi.attach(actor)
	return actor


func test_qi_regen_rate() -> void:
	var actor := _actor_with_module()
	# (20 * 0.3 + 10 * 0.1) * 1.0 = 7.0
	assert_almost_eq(actor.stats.derived(QiStats.QI_REGEN_RATE), 7.0, "regen rate")


func test_qi_absorption() -> void:
	var actor := _actor_with_module()
	# (20 * 0.5 + 10 * 0.2) * (0.5 + 1.0 * 0.5) = 12.0 * 1.0 = 12.0
	assert_almost_eq(actor.stats.derived(QiStats.QI_ABSORPTION), 12.0, "absorption")


func test_technique_cost_reduction() -> void:
	var actor := _actor_with_module()
	# clamp(15 * 0.002, 0, 0.5) = 0.03
	assert_almost_eq(actor.stats.derived(QiStats.TECHNIQUE_COST_REDUCTION), 0.03, "cost reduction")


func test_technique_power() -> void:
	var actor := _actor_with_module()
	# (1.0 + 20 * 0.05) * (0.5 + 1.0 * 0.5) * 1.0 = 2.0 * 1.0 = 2.0
	assert_almost_eq(actor.stats.derived(QiStats.TECHNIQUE_POWER), 2.0, "technique power")


func test_flight_speed() -> void:
	var actor := _actor_with_module()
	# 30 * 2.0 * (1.0 + 0 * 0.05) = 60.0
	assert_almost_eq(actor.stats.derived(QiStats.FLIGHT_SPEED), 60.0, "flight speed")


func test_qi_sense_range() -> void:
	var actor := _actor_with_module()
	# (20 * 10 + 15 * 5) * (0.5 + 1.0 * 0.5) = 275 * 1.0 = 275
	assert_almost_eq(actor.stats.derived(QiStats.QI_SENSE_RANGE), 275.0, "sense range")


func test_realm_scaling() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	# R1 is the ladder's first ordinal, so the factor is neutral.
	assert_almost_eq(actor.stats.derived(QiStats.QI_REGEN_RATE), 7.0, "rank 0 regen")
	actor.path(QiPath.PATH_ID).rank_id = &"spirit_sea"
	# Derive the expectation from the code under test. This suite used to derive
	# it from the seed's authored field, and then from a shared ladder, and stayed
	# green through both changes — which is how a provider can move three times
	# without a test noticing.
	var factor := RealmRate.factor(&"spirit_sea")
	var rank_10: float = actor.stats.derived(QiStats.QI_REGEN_RATE)
	assert_almost_eq(rank_10, 7.0 * factor, "rank 10 regen")
	# the point of the test: a higher rank must actually regen faster
	assert_eq(rank_10 > 7.0, true, "rank 10 outranks rank 0")
	assert_almost_eq(
		actor.stats.derived(QiStats.TECHNIQUE_POWER), 2.0 * factor, "rank 10 technique power"
	)


## Nothing the provider emits may be scaled by anything but the bounded rate. The
## realm MAGNITUDE lives in `RealmScaling` (core) and `dantian_capacity`, so a
## larger factor here would count the same realm twice — and at the top realm it
## would fill the reservoir faster than any authored budget could price.
func test_no_stat_is_scaled_by_anything_but_the_bounded_rate() -> void:
	var plain := _actor_with_module()
	var actor := _actor_with_module()
	actor.set_path(PathState.new(QiPath.PATH_ID, &"primordial_origin"))
	var factor := RealmRate.factor(&"primordial_origin")
	for stat_id in [
		QiStats.QI_REGEN_RATE,
		QiStats.TECHNIQUE_POWER,
		QiStats.FLIGHT_SPEED,
	]:
		assert_almost_eq(
			actor.stats.derived(stat_id) / plain.stats.derived(stat_id),
			factor,
			"%s is exactly the rate" % String(stat_id),
			0.0001
		)
	# The ids with no realm read at all must be untouched by a path at R30.
	assert_almost_eq(
		actor.stats.derived(QiStats.QI_ABSORPTION),
		plain.stats.derived(QiStats.QI_ABSORPTION),
		"absorption carries no realm factor",
		0.0001
	)


func test_absorption_is_not_scaled_by_a_second_qi_axis() -> void:
	# The removed `qi_purity` pool multiplied absorption by (0.5 + purity * 0.5).
	# It was created full and never written, so the factor was always 1.0 — a
	# latent gate with no action behind it. Absorption is now base-only: the
	# meridian flow bonus is the only multiplier here.
	var actor := _actor_with_module()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(QiStats.QI_ABSORPTION), 12.0 * 1.10, "absorption with a meridian"
	)


func test_meridian_bonus_applies_to_regen() -> void:
	var actor := _actor_with_module()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.mark_stats_dirty()
	# flow bonus = 0.10, regen = 7.0 * 1.10 = 7.7
	assert_almost_eq(actor.stats.derived(QiStats.QI_REGEN_RATE), 7.7, "meridian bonus regen")


func test_meridian_bonus_applies_to_absorption() -> void:
	var actor := _actor_with_module()
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.mark_stats_dirty()
	# flow bonus = 0.10, absorption = 12.0 * 1.10 = 13.2
	assert_almost_eq(actor.stats.derived(QiStats.QI_ABSORPTION), 13.2, "meridian bonus absorption")


func test_no_meridian_bonus_when_closed() -> void:
	var actor := _actor_with_module()
	# no meridians opened, flow bonus = 0.0
	assert_almost_eq(actor.stats.derived(QiStats.QI_REGEN_RATE), 7.0, "no meridian bonus")
