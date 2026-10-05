extends TestCase

## ADR 0013: stat and resource id constants for the mind_cultivation module.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


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
	# ADR 0071 / BL-0114: RENAMED. These are NOT core's `Stat.CRIT_CHANCE` /
	# `Stat.EVASION`, and ADR 0071's `MindDamage` is their only consumer -- so the
	# ids are asserted here as a RESERVATION, which is what the rename bought: no
	# qi/body surface may read them, and a second combat module cannot adopt them by
	# accident.
	assert_eq(String(MindStats.MIND_FOCUS_CHANCE), "mind_focus_chance", "mind_focus_chance id")
	assert_eq(String(MindStats.MIND_AVOIDANCE), "mind_avoidance", "mind_avoidance id")
	assert_eq(
		String(MindStats.MIND_FOCUS_CHANCE) == String(Stat.CRIT_CHANCE),
		false,
		"mind focus chance is NOT core's crit chance"
	)
	assert_eq(
		String(MindStats.MIND_AVOIDANCE) == String(Stat.EVASION),
		false,
		"mind avoidance is NOT core's evasion"
	)
	assert_eq(
		String(MindStats.ILLUSION_RESISTANCE), "illusion_resistance", "illusion_resistance id"
	)
	assert_eq(
		String(MindStats.MIND_TECHNIQUE_POWER), "mind_technique_power", "mind_technique_power id"
	)


## BL-0163: four ids the module used to publish and nothing read. They are gone,
## and this is the assertion that says so. It reads SOURCE across the whole module
## rather than only the live values, because that is the one thing that can catch a
## deleted id being reintroduced under a second name: a numerically identical
## private copy of a deleted rate is invisible to every value assertion, which is
## the trap `test_realm_rate.gd` closes for the realm rate. The runtime half a
## source read cannot reach -- that nothing derives them any more -- is the second
## loop. `Probe.module_code_all` strips comment lines, because the docblocks
## recording WHY each id was deleted necessarily spell the ids out.
func test_the_deleted_sea_and_rate_ids_stay_deleted() -> void:
	for gone in ["comprehension_bonus", "sea_clarity", "sea_turbulence", "sea_full"]:
		assert_eq(
			Probe.module_code_all().contains(gone),
			false,
			"no file in mind_cultivation declares or emits %s" % gone
		)
		var actor := Actor.new(&"probe", {})
		MindCultivationApi.attach(actor)
		MindCultivationApi.attach_sea(actor)
		actor.mark_stats_dirty()
		assert_eq(
			actor.stats.derived_all().has(StringName(gone)), false, "%s is not derived" % gone
		)
