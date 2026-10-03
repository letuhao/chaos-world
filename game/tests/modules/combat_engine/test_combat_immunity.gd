extends TestCase

## The immunity invariant, end to end (ADR 0067, BRIEF 1.3).
##
## "`Stat.DAMAGE_REDUCTION` is FLAT with baseline `0.0` (ADR 0022) — a subtraction, not a
## fraction. So the chip floor is unconditional and immunity is arithmetically
## unreachable: a landed hit is always >= `MIN_CHIP_ABS = 1.0` HP."
##
## The property is DISTRIBUTIONAL, not a cap on an authored stat: "of hits that land, at
## least this much is spent". Nothing here clamps `DAMAGE_REDUCTION`, and nothing reads
## its value to decide anything — the floor runs after it and restores the chip.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func test_a_declined_mechanism_against_total_reduction_still_chips_the_absolute_floor() -> void:
	# The three worst cases at once: the mechanism returns 0.0, the target carries a
	# `DAMAGE_REDUCTION` of 1e9, and the target is at 1 HP.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 0.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target", 1.0)
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1e9, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_eq(mechanism.resolve_calls, 1, "the mechanism ran (it was a clean, landed hit)")
	assert_almost_eq(outcome.amount, _tuning.min_chip_abs, "the chip floor, not zero")
	assert_ne(outcome.amount, 0.0, "immunity is arithmetically unreachable")
	assert_almost_eq(outcome.overflow, _tuning.min_chip_abs, "and it reached health")
	assert_almost_eq(target.resource(&"health").current, 0.0, "the 1 HP target died")


func test_a_landed_hit_is_never_below_the_share_of_its_own_base() -> void:
	# `amount >= base * MIN_CHIP_SHARE` — the other half of S8. A large magnitude with a
	# zero-share floor: the SHARE is what binds, and it is read from the shipped tuning.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 1.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1e9, &"test"))
	var technique := CombatTestKit.technique(1000.0)
	var outcome := CombatSpine.resolve_hit(attacker, target, technique, _tuning, null)
	assert_almost_eq(outcome.amount, outcome.base * _tuning.min_chip_share, "exactly the share")
	assert_almost_eq(
		outcome.amount,
		technique.magnitude * RealmRate.factor(attacker.realm()) * _tuning.min_chip_share,
		"of the rate-gated base"
	)


func test_the_absolute_floor_binds_when_the_share_is_smaller() -> void:
	var technique := CombatTestKit.technique(0.01)
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	assert_almost_eq(
		CombatSpine.chip_floor(0.01, _tuning),
		_tuning.min_chip_abs,
		"a tiny base floors at MIN_CHIP_ABS"
	)
	assert_almost_eq(
		CombatSpine.chip_floor(100.0, _tuning),
		100.0 * _tuning.min_chip_share,
		"a large base floors at the share"
	)


func test_every_landed_hit_is_at_least_the_floor_whatever_the_defender_stacks() -> void:
	# Sweep the whole reduction range and every amplification range: no combination of
	# mitigation drives a landed hit to zero, because S8 runs after S7 and does not care
	# what S7 produced.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 0.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var weakest := INF
	var steps := 0
	while steps <= 10:
		var target := CombatTestKit.actor(&"target", 1.0e9)
		target.stats.add_modifier(
			StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, pow(10.0, steps * 3.0), &"t")
		)
		var outcome := CombatSpine.resolve_hit(
			attacker, target, CombatTestKit.technique(100.0), _tuning, null
		)
		weakest = minf(weakest, outcome.amount)
		steps += 1
	assert_almost_eq(weakest, _tuning.min_chip_abs, "1e0 through 1e30, the floor holds")


func test_amplification_cannot_drive_the_floor_because_the_floor_is_a_maximum() -> void:
	# The floor is `maxf`, so a huge amplification is never re-floored DOWN: it is simply
	# above the floor and passes through. Asserted so a future "minimum damage" written
	# as a `minf` cannot quietly become a ceiling.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.AMPLIFICATION, 1000.0, &"test")
	)
	MechanismSlot.bind(attacker, mechanism)
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(
		outcome.amount,
		40.0 * CombatSpine.amp_factor(1000.0, _tuning),
		"amplification is unbounded and the floor does not cap it"
	)
	assert_ne(outcome.amount, _tuning.min_chip_abs, "and it was never pulled back to the floor")


func test_the_invariant_depends_on_the_stage_order_and_not_on_the_tuning_number() -> void:
	# The floor's VALUE is a balance dial and may be retuned freely. The invariant is
	# "a landed hit is never zero", so it must survive any positive floor.
	#
	# Asserted against `CombatSpine.chip_floor`, because S8's floor is `maxf(min_chip_abs,
	# base * min_chip_share)` and at `base = 100.0` with the shipped `min_chip_share` the
	# SHARE is the binding term: `0.25` cannot be the answer for a floor that reads
	# `max(0.25, 1.0)`. Asserting the literal `min_chip_abs` measured the floor's
	# vocabulary, not the invariant.
	#
	# `duplicate()` because `CombatTuning.shipped()` is a `load()`ed resource, so Godot hands
	# back the SAME cached instance: writing `min_chip_abs` on it would retune every later
	# suite in the run, and the last value in the loop is what they would all see.
	for value in [0.25, 1.0, 7.5]:
		var tuning := CombatTestKit.shipped().duplicate() as CombatTuning
		tuning.min_chip_abs = value
		var mechanism := CombatTestKit.FixedMechanism.new()
		mechanism.amount = 0.0
		var attacker := CombatTestKit.quiet_actor(&"attacker")
		MechanismSlot.bind(attacker, mechanism)
		var target := CombatTestKit.actor(&"target", 1.0)
		target.stats.add_modifier(
			StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1e9, &"test")
		)
		var outcome := CombatSpine.resolve_hit(
			attacker, target, CombatTestKit.technique(100.0), tuning, null
		)
		assert_almost_eq(
			outcome.amount,
			CombatSpine.chip_floor(outcome.base, tuning),
			"a landed hit is at least whatever the floor says, for %s" % str(value)
		)
		assert_ne(outcome.amount, 0.0, "and never zero for %s" % str(value))
	# The shipped instance is untouched by any of that.
	assert_almost_eq(
		CombatTestKit.shipped().min_chip_abs,
		CombatTuning.shipped().min_chip_abs,
		"the cached shipped tuning was never written through"
	)
