extends TestCase

## ADR 0013: the mind_cultivation module contributes its stats through a
## StatProvider, and ADR 0016: the realm rate scales the technique output.
##
## Every test here runs on an actor that actually holds a mind path at a named
## rank. A pathless actor scores the neutral factor (1.0), so a suite that forgets
## `set_path` passes while proving nothing about the realm profile — that is
## exactly the trap `test_mind_power_curve.gd` now guards.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## Spirit tier, ladder position 11 (index 10; the Spirit tier starts at index 9).
## Mind's mental output takes the bounded per-realm rate, so `RANK`'s value comes
## from the profile class rather than from a literal.
const RANK := &"spirit_sea"

## Base attributes below make the pre-factor value 50.0 technique power
## (20 * 2.5) and 70.0 mental attack (20 * 3.5); the defence reads will (ADR 0900).
const BASE_TECHNIQUE_POWER := 50.0
const BASE_MENTAL_ATTACK := 70.0
const BASE_MENTAL_DEFENSE := 25.0


## The rate for the reference realm, read from the profile rather than restated.
## It used to be a literal derived from Mind's private 601x budget, which is how
## this suite kept passing while the game moved off that curve, and then off the
## shared ladder. Deriving it means a retune of the step lands here as a real
## failure.
func _rate() -> float:
	return RealmRate.factor(RANK)


## An actor with the module attached and NO path: the rate is neutral (1.0),
## which is the documented reference, not an accident of a failed profile lookup.
func _actor_without_path() -> Actor:
	var actor := _bare_actor()
	MindCultivationApi.attach(actor)
	return actor


## An actor with the module attached and a mind path at `rank_id`, so the
## provider resolves that realm's profile factors.
func _actor_at_rank(rank_id: StringName) -> Actor:
	var actor := _actor_without_path()
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	return actor


func _bare_actor() -> Actor:
	return (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
			}
		)
	)


func test_attach_adds_resources() -> void:
	var actor := _actor_at_rank(RANK)
	assert_eq(actor.resource(MindStats.MIND_POWER) != null, true, "mind_power pool")
	assert_eq(actor.resource(MindStats.AWARENESS) != null, true, "awareness pool")


func test_mental_attack_scales_with_perception() -> void:
	var actor := _actor_at_rank(RANK)
	# 70.0 * T
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_ATTACK),
		BASE_MENTAL_ATTACK * _rate(),
		"mental attack",
		0.01
	)


func test_mental_defense_scales_with_will() -> void:
	var actor := _actor_at_rank(RANK)
	# 25.0 * T
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		BASE_MENTAL_DEFENSE * _rate(),
		"mental defense",
		0.01
	)


func test_illusion_resistance_from_will() -> void:
	var actor := _actor_at_rank(RANK)
	# Factor-free will read: 10 * 0.006
	assert_almost_eq(
		actor.stats.derived(MindStats.ILLUSION_RESISTANCE), 0.06, "illusion resistance"
	)


func test_mind_technique_power_scales() -> void:
	var actor := _actor_at_rank(RANK)
	# 45.0 * T
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		BASE_TECHNIQUE_POWER * _rate(),
		"technique power",
		0.01
	)


func test_spiritual_sense_range_grows_with_the_rate() -> void:
	var actor := _actor_at_rank(RANK)
	# 50.0 + 20 * 5.0 + T * 10.0
	assert_almost_eq(
		actor.stats.derived(MindStats.SPIRITUAL_SENSE_RANGE),
		150.0 + _rate() * 10.0,
		"spiritual sense range",
		0.01
	)


## `comprehension_bonus` is DELETED (BL-0163) and this test now asserts why it
## must not come back. It was `1.0 + comprehension * 0.01 + technique_factor *
## 0.02` -- core's `Stat.INSIGHT_GAIN` term for comprehension gain, plus a second
## realm-rate term on it -- and nothing read it. With `MindTraining._grant_insight`
## now pricing the mind path's comprehension through `Stat.INSIGHT_GAIN`, keeping
## it would have made one gate read two divergent multipliers: the ADR 0116
## duplicate-rate failure, and the same shape ADR 0071 deleted for
## `critical_chance`/`dodge_chance`.
##
## The second half is a source read because a numerically identical private copy
## of a deleted rate is invisible to every value test: what has to be impossible
## is the DECLARATION, not the arithmetic. `Probe.module_code` strips comment
## lines so the docblock recording the deletion cannot fail its own guard.
func test_the_module_publishes_no_comprehension_rate_of_its_own() -> void:
	var actor := _actor_at_rank(RANK)
	var emitted: Dictionary = MindProvider.new().contribute(actor.stats._context)
	for key in emitted:
		assert_eq(
			String(key).contains("comprehension"),
			false,
			"the provider emits no comprehension dial (%s)" % String(key)
		)
	assert_eq(
		Probe.module_code("stats.gd").contains("comprehension_bonus"),
		false,
		"and MindStats declares no comprehension_bonus id"
	)
	# The one rate that remains is core's, and it is the one the gate is read
	# through -- asserted in test_mind_insight_rate.gd, behaviourally.


func test_meridian_strengthening_boosts_technique_power() -> void:
	var actor := _actor_at_rank(RANK)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	# 50.0 * T * (1 + 0.05 power bonus)
	var expected := BASE_TECHNIQUE_POWER * _rate() * 1.05
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		expected,
		"meridian boosts technique power",
		0.01
	)


func test_meridian_strengthening_boosts_mental_defense() -> void:
	var actor := _actor_at_rank(RANK)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	# 25.0 * T * (1 + 0.05 power bonus)
	var expected := BASE_MENTAL_DEFENSE * _rate() * 1.05
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_DEFENSE),
		expected,
		"meridian boosts mental defense",
		0.01
	)


func test_no_meridian_bonus_without_strengthening() -> void:
	var actor := _actor_at_rank(RANK)
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.mark_stats_dirty()
	# Opening a realm's meridians is not a power bonus: they are still closed.
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		BASE_TECHNIQUE_POWER * _rate(),
		"no meridian bonus",
		0.01
	)


## The neutral reference. T is 1.0 without a path, and R1 has P = 1, so both
## score the unfactored base — but only because they are the reference, not
## because the profile lookup silently failed.
func test_factors_are_neutral_without_a_path() -> void:
	var actor := _actor_without_path()
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_ATTACK), BASE_MENTAL_ATTACK, "no path attack", 0.01
	)
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		BASE_TECHNIQUE_POWER,
		"no path technique power",
		0.01
	)


func test_r1_is_the_neutral_realm() -> void:
	var actor := _actor_at_rank(&"qi_refining")
	assert_almost_eq(
		actor.stats.derived(MindStats.MIND_TECHNIQUE_POWER),
		BASE_TECHNIQUE_POWER,
		"R1 is the 1.0 factor reference",
		0.01
	)


## `attach` installs exactly one MindProvider into the actor's stats. The facade
## deliberately does not hand the module's provider type back to callers, so
## installation is asserted where it actually happens: in ActorStats.
func test_provider_installed_once() -> void:
	var actor := _actor_at_rank(RANK)
	var installed := 0
	for entry in actor.stats._providers:
		if entry is MindProvider:
			installed += 1
	assert_eq(installed, 1, "attach installs exactly one MindProvider")
	# Idempotent: a second attach must not stack a duplicate provider, which
	# would double every Mind contribution.
	MindCultivationApi.attach(actor)
	var again := 0
	for entry in actor.stats._providers:
		if entry is MindProvider:
			again += 1
	assert_eq(again, 1, "attach is idempotent")
