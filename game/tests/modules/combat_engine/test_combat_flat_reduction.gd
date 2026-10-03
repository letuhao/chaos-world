extends TestCase

## S5 and S8: reduction runs, THEN the floor restores the chip (ADR 0067).
##
## Two properties, and the second is the one people get wrong:
##
## 1. `Stat.DAMAGE_REDUCTION = 0.0` is the AUTHORED BASELINE (ADR 0022). A target nobody
##    has invested anything into must produce a result BYTE-IDENTICAL to one where the
##    channel does not exist — not "close", not "within an epsilon". A spine that adds a
##    `0.0001` anywhere on the reduction path is a spine whose floor is reachable and
##    whose chip is wrong.
## 2. The ordering. Reduction first, floor second.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the authored baseline is the identity -------------------------------------


func test_the_authored_baseline_is_byte_identical_to_no_reduction() -> void:
	# Two targets: one carrying an explicit `0.0` FLAT on `Stat.DAMAGE_REDUCTION`, one
	# carrying nothing at all. Exactly equal, not almost.
	var explicit := CombatTestKit.actor(&"target")
	explicit.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 0.0, &"test"))
	var implicit := CombatTestKit.actor(&"target")
	assert_almost_eq(explicit.stats.derived(Stat.DAMAGE_REDUCTION), 0.0, "the baseline is 0.0")
	assert_almost_eq(
		explicit.stats.derived(Stat.DAMAGE_REDUCTION),
		implicit.stats.derived(Stat.DAMAGE_REDUCTION),
		"and it is indistinguishable from the channel not existing"
	)
	var with_explicit := _resolve_against(explicit, 40.0)
	var with_implicit := _resolve_against(implicit, 40.0)
	assert_eq(with_explicit.amount, with_implicit.amount, "the amounts are exactly equal")
	assert_eq(with_explicit.overflow, with_implicit.overflow, "and so are the overflows")
	assert_eq(with_explicit.proposed_amount(), with_implicit.proposed_amount(), "and the proposals")


func test_the_combat_reduction_channel_is_also_identical_at_its_baseline() -> void:
	# `CombatStats.REDUCTION` is this module's own flat subtraction and defaults to 0.0,
	# so an explicit 0.0 on it must also be the identity.
	var explicit := CombatTestKit.actor(&"target")
	explicit.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REDUCTION, 0.0, &"test"))
	var implicit := CombatTestKit.actor(&"target")
	assert_eq(
		_resolve_against(explicit, 40.0).amount,
		_resolve_against(implicit, 40.0).amount,
		"a 0.0 CombatStats.REDUCTION is the identity too"
	)


func test_both_reduction_channels_sum_rather_than_erase() -> void:
	# `REDUCTION` and `Stat.DAMAGE_REDUCTION` are alternatives expressing the same
	# intent. An author who authors both halves their own mitigation — the loud mistake —
	# rather than one silently erasing the other, which is the quiet one.
	var both := CombatTestKit.actor(&"target")
	both.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 4.0, &"test"))
	both.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REDUCTION, 4.0, &"test"))
	var one := CombatTestKit.actor(&"target")
	one.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 4.0, &"test"))
	var twice := CombatSpine.amp_factor(-8.0, _tuning)
	var once := CombatSpine.amp_factor(-4.0, _tuning)
	assert_almost_eq(
		_resolve_against(both, 40.0).amount, 40.0 * twice, "8.0 of reduction applies twice over"
	)
	assert_almost_eq(
		_resolve_against(one, 40.0).amount,
		40.0 * once,
		"4.0 applies once, so the two really do differ"
	)


# --- S5 / S8 ordering -----------------------------------------------------------


func test_reduction_then_floor_is_the_only_ordering_that_keeps_the_invariant() -> void:
	# Stated as the two arithmetic orders on the same numbers, so the ordering is a claim
	# about code rather than about intent. Floor-then-reduce returns 0.0 and a landed hit
	# costs nothing — which is exactly the defect ADR 0067 says this pair prevents.
	var amount := 4.0
	var factor := CombatSpine.amp_factor(-9.0, _tuning)
	var floor := _tuning.min_chip_abs
	var reduce_then_floor := maxf(amount * factor, floor)
	var floor_then_reduce := maxf(amount, floor) * factor
	assert_almost_eq(reduce_then_floor, floor, "reduce, then floor: the chip survives")
	assert_almost_eq(floor_then_reduce, 0.4, "floor, then reduce: the chip is gone")
	assert_ne(reduce_then_floor, floor_then_reduce, "the order is load-bearing")


func test_a_crit_does_not_survive_enough_reduction_on_its_own() -> void:
	# The reason the floor has to run after S7 AND after S6: a crit is a multiplication,
	# so a large enough reduction divides it back down. Without the floor it would be
	# zero; with it, it is the chip.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 1.0
	var attacker := CombatTestKit.actor(&"attacker")
	attacker.stats.add_modifier(StatModifier.new(Stat.CRIT_CHANCE, Stat.Op.FLAT, 1.0, &"test"))
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 9.0, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, _zero_draws()
	)
	assert_eq(outcome.crit, true, "a crit landed")
	assert_almost_eq(outcome.amount, _tuning.min_chip_abs, "and the floor still holds")


# --- the shape of the factor ----------------------------------------------------


func test_the_factor_is_linear_in_delta_and_floored_at_zero() -> void:
	# ADR 0067's S7, stated as the shape it must be: ONE linear factor `1 + d / amp_scale`
	# floored at zero, so `d == -amp_scale` is a total refusal and the factor never divides
	# by anything computed.
	#
	# This test used to be named `..._is_reciprocal_and_asymptotic` and asserted
	# `f(-5) == 2.0` and `f(-9) == 10.0` — a factor that GROWS as a defender stacks
	# reduction, which is the wrong sign for a damage term, and which contradicts this
	# file's own `test_reduction_then_floor_is_the_only_ordering_that_keeps_the_invariant`,
	# demanding `f(-9) == 0.1`. Two tests, one function, 100x apart: no implementation could
	# satisfy both. ADR 0067 refuses `AmpFactorReciprocal` by name, so the reciprocal was
	# the half that was wrong, not the floor.
	assert_almost_eq(CombatSpine.amp_factor(0.0, _tuning), 1.0, "neutral is 1.0")
	assert_almost_eq(CombatSpine.amp_factor(5.0, _tuning), 1.5, "half the scale is half again")
	assert_almost_eq(
		CombatSpine.amp_factor(-5.0, _tuning), 0.5, "half the scale negative halves the amount"
	)
	assert_almost_eq(CombatSpine.amp_factor(-9.0, _tuning), 0.1, "linear all the way down")
	assert_almost_eq(
		CombatSpine.amp_factor(5.0, _tuning) / CombatSpine.amp_factor(-5.0, _tuning),
		3.0,
		"and the two halves of the scale are mirror images"
	)


func test_the_factor_never_goes_negative_at_or_past_its_floor() -> void:
	# A `DAMAGE_REDUCTION` past the floor is an authored refusal, so the factor reads
	# exactly `0.0` and never keeps counting down into a negative refund — which S9's one
	# sign flip would otherwise spend as a heal.
	assert_almost_eq(
		CombatSpine.amp_factor(-_tuning.amp_scale, _tuning), 0.0, "exactly at the floor"
	)
	assert_almost_eq(CombatSpine.amp_factor(-1e9, _tuning), 0.0, "and far past it")
	assert_eq(is_finite(CombatSpine.amp_factor(-1e9, _tuning)), true, "still finite")
	# A tuning with no scale is a caller who supplied no contest, so the factor is the
	# identity rather than the `0.0 / 0.0` NaN `maxf` passes straight through to S8.
	assert_almost_eq(CombatSpine.amp_factor(0.0, CombatTestKit.bare()), 1.0, "no scale, no contest")
	assert_almost_eq(CombatSpine.amp_factor(-1e9, CombatTestKit.bare()), 1.0, "and never a NaN")


func test_no_reduction_and_no_amplification_is_exactly_one() -> void:
	# The byte-identical property stated at the factor's level: the common case is the
	# identity, not a near-miss.
	assert_eq(CombatSpine.amp_factor(0.0, _tuning), 1.0, "the identity factor")
	var outcome := _resolve_against(CombatTestKit.actor(&"target"), 40.0)
	assert_almost_eq(
		outcome.amount, 40.0 * CombatSpine.amp_factor(0.0, _tuning), "so 40.0 stays 40.0"
	)


# --- internals -----------------------------------------------------------------


func _resolve_against(target: Actor, amount: float) -> CombatOutcome:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = amount
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(attacker, target, CombatTestKit.technique(100.0), _tuning, null)


func _zero_draws() -> CombatTestKit.CountingGenerator:
	return CombatTestKit.CountingGenerator.new([0.0])
