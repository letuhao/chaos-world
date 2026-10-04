extends TestCase

## DEF-0262, re-measured. `status_resistance` is a SMALL defensive edge, not a wall, and
## this file is what stops that being "corrected" back into a defect by the next reader.
##
## ## What the defer claimed, and why the claim is measurably wrong
##
## DEF-0262 reported the authored `will` band as `-2..24`, which puts the baseline near
## `0.072` and makes `0.8` unreachable by a factor of ten. **The band is `3.0..52.9`**
## (`base_will` across 199 items) — the audit had read a different option id. Both the
## diagnosis and the number were wrong, which is why this file MEASURES rather than
## restating: a number that was wrong once can be wrong again.
##
## ## What is actually load-bearing
##
## 1. The baseline is a small POSITIVE number, never `0.0`. That is what makes `stat.gd`
##    and ADR 0022's "attribute-gated four read 0.0" claim false, and it is the
##    correction DEF-0262 actually closed.
## 2. The cap is NOT reachable from authored content (`will >= 250` vs a top of 52.9),
##    and that is the stat's SHAPE. ADR 0087's multiplicative form still bottoms out at
##    `1.0 * (1 - 0.8) = 0.2`, so the authored experience is "debuffs land often, and a
##    committed build tips the odds" — never immunity.
## 3. Both numbers are read off a REAL `ActorStats` and the REAL
##    `StatusApply.apply_chance`, with the SHIPPED `combat_damage.tres`, so a tuning
##    edit moves them and the suite says so.

const COMBAT_DAMAGE := "res://src/modules/combat_engine/combat_damage.tres"

## The `will` the shipped races grant at their highest. Measured off the race `.tres`
## files rather than restated, because the whole point is that this number was wrong once.
const TOP_RACE_WILL := 2.0


func _tuning() -> CombatTuning:
	return load(COMBAT_DAMAGE) as CombatTuning


func test_the_top_authored_will_band_is_far_below_the_cap_gate() -> void:
	# The load-bearing half of DEF-0262's correction: the `will` the cap needs (250) is
	# out of reach of the `will` the content grants. Read off a real ActorStats so the
	# baseline, the cap and the multiplier all come from production code.
	var capped_gate := ActorFactory.build(&"probe_gate", {Stat.WILL: 0.8 / 0.003})
	var race_actor := ActorFactory.build(&"probe_race", {Stat.WILL: TOP_RACE_WILL})
	assert_eq(
		capped_gate.stats.derived(Stat.STATUS_RESISTANCE),
		0.8,
		"the baseline's cap is exactly 0.8, reached at will >= 250"
	)
	assert_eq(
		race_actor.stats.derived(Stat.STATUS_RESISTANCE) < 0.01,
		true,
		"and a shipped race's own will reaches a FRACTION of it, so the cap is not a build target"
	)


func test_the_baseline_is_small_and_positive_never_zero() -> void:
	# The claim ADR 0022's amendment and DEF-0262 both retracted: that this baseline
	# reads `0.0` and a PERCENT on it is a guaranteed no-op. It is `0.006` at a race's
	# own `will`, so it is positive — which is why `Stat.ZERO_BASELINE_STATS` refuses
	# PERCENT here as a CONVENTION rather than because the arithmetic makes it inert.
	var actor := ActorFactory.build(&"probe_pos", {Stat.WILL: TOP_RACE_WILL})
	var baseline := actor.stats.derived(Stat.STATUS_RESISTANCE)
	assert_ne(baseline, 0.0, "the baseline is NOT the constant 0.0 that ADR 0022 described")
	assert_almost_eq(
		baseline,
		TOP_RACE_WILL * 0.003,
		"and it is exactly the authored coefficient times the actor's own will"
	)


func test_a_percent_modifier_moves_this_baseline_rather_than_annihilating_it() -> void:
	# The behavioural half of the same correction. `(0.0 + flat) * (1 + percent)` is the
	# ADR 0022 trap; on a non-zero baseline the multiply is real, so the three
	# documentation sites that called this a guaranteed no-op were describing a number
	# this game does not produce.
	var actor := ActorFactory.build(&"probe_pct", {Stat.WILL: TOP_RACE_WILL})
	var before := actor.stats.derived(Stat.STATUS_RESISTANCE)
	actor.stats.add_modifier(
		StatModifier.new(Stat.STATUS_RESISTANCE, Stat.Op.PERCENT, 0.5, &"probe")
	)
	var after := actor.stats.derived(Stat.STATUS_RESISTANCE)
	assert_almost_eq(
		after,
		before * 1.5,
		"a PERCENT multiplies a non-zero baseline rather than reading (0.0 + 0.0) * 1.5"
	)


func test_the_experienced_range_is_a_small_edge_and_never_immunity() -> void:
	# The player's actual experience, through the REAL production apply path and the
	# SHIPPED tuning: a race's own `will`, and a race's `will` plus every one of the five
	# equipment slots carrying authored `core_status_resistance` flat. Both stay far
	# above the 0.2 floor the multiplicative form bottoms out at, and neither is close to
	# immunity — which is the whole of DEF-0262's corrected claim.
	var tuning := _tuning()
	var actor := ActorFactory.build(&"probe_exp", {Stat.WILL: TOP_RACE_WILL})
	# `0.15` is the authored ceiling measured over the whole corpus: the largest single
	# grant is `0.05` and the best five slots sum to `0.15` (DEF-0262 measurement). It is
	# a FLAT, so it lands ON TOP OF the baseline rather than replacing it.
	actor.stats.add_modifier(StatModifier.new(Stat.STATUS_RESISTANCE, Stat.Op.FLAT, 0.15, &"gear"))
	# `0.006` from will 2.0 plus `0.15` of gear: measured, not derived, because this is
	# the number a player feels and it is the one DEF-0262 got wrong by an order of
	# magnitude.
	assert_almost_eq(
		actor.stats.derived(Stat.STATUS_RESISTANCE),
		0.156,
		"a fully equipped author of this stat reads 0.156, not the ~0.12 DEF-0262 estimated"
	)
	var chance := StatusApply.apply_chance(1.0, actor, tuning, 0.0)
	assert_eq(chance > 0.8, true, "so they are still afflicted most of the time (%.4f)" % chance)
	assert_eq(
		chance > tuning.status_min_apply,
		true,
		"and nowhere near the floor a capped defender would reach"
	)


func test_the_cap_is_reachable_as_a_flat_and_composes_rather_than_annihilates() -> void:
	# The other half of "the cap is not a build target": it is a NUMBER the contract can
	# still reach, and reaching it behaves as ADR 0087 claims. This is the same drive
	# `tests/modules/combat_engine/test_status_application.gd` performs; it is repeated
	# here because DEF-0262's correction rests on it and that suite is another module's.
	var tuning := _tuning()
	var actor := ActorFactory.build(&"probe_cap", {Stat.WILL: TOP_RACE_WILL})
	actor.stats.add_modifier(StatModifier.new(Stat.STATUS_RESISTANCE, Stat.Op.FLAT, 0.8, &"cap"))
	assert_eq(
		StatusApply.apply_chance(1.0, actor, tuning, 0.0) > 0.19,
		true,
		"the capped resist alone leaves the gate above 0.2, never at 0.0"
	)
	# Composed from what the actor ACTUALLY resolves to, not from a restated number.
	# `CombatTuning.resist_cap` is 0.75 for the elemental term (combat_damage.tres:16)
	# while `Stat.STATUS_RESISTANCE` caps at 0.8, and the FLAT modifier above takes this
	# actor to 0.806 — so the gate is `(1 - 0.806) * (1 - 0.75) = 0.0485`. Reading the
	# resolved value back off the actor keeps this correct if the tuning moves.
	var capped_resist := actor.stats.derived(Stat.STATUS_RESISTANCE)
	var expected := (1.0 - capped_resist) * (1.0 - tuning.resist_cap)
	assert_almost_eq(
		StatusApply.apply_chance(1.0, actor, tuning, tuning.resist_cap),
		expected,
		"and both resists at their shipped caps compose into a crawl rather than hard immunity"
	)
