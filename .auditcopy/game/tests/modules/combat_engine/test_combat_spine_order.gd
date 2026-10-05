extends TestCase

## The four load-bearing orderings of ADR 0067's spine, each independently assertable.
##
## ADR 0067: "Every stage is one private function, so each ordering above is a two-line
## test rather than a debate." This file is that test.
##
## 1. **S1 before S2** — the realm ladder must not make a hit land MORE OFTEN. Were it to
##    move `p_hit`, it would be an invisible second dial on `Stat.EVASION`.
## 2. **S2 before S4** — a miss never invokes a mechanism.
## 3. **S4 before S6** — crit multiplies what the mechanism produced and is never an
##    INPUT to it, so the three mechanisms cannot disagree on a shared stat.
## 4. **S7 before S8, S8 before S9** — reduction runs, THEN the floor restores the chip.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- 1. S1 before S2 -----------------------------------------------------------


func test_the_ladder_gate_scales_magnitude_and_never_the_landed_chance() -> void:
	# The same defender, the same band, two attackers on different realms. A landed
	# chance that moved with the realm would be the second dial.
	var defender := CombatTestKit.actor(&"target")
	var weak := _attacker_at(&"weak", &"qi_refining")
	var strong := _attacker_at(&"strong", &"nascent_soul")
	assert_ne(
		CombatSpine.base_damage(weak, CombatTestKit.technique(100.0)),
		CombatSpine.base_damage(strong, CombatTestKit.technique(100.0)),
		"the ladder moves magnitude at all"
	)
	# Same number of band rolls for both, and neither attacker has any accuracy: the
	# defender's `Stat.EVASION` is the only term in `p_hit`, and it does not read the
	# attacker's realm. Asserted structurally — `_landed_chance` is private, so this
	# pins the property through the roll it feeds rather than reaching past it.
	#
	# ZERO draws, not one: this defender is fully statted for nothing, so `p_hit` is
	# saturated at 1.0 and there is no parry or block band left to consume a draw. That is
	# the same rule `test_combat_band_roll.gd::test_a_saturated_landed_chance_consumes_no_draw`
	# states, and this assertion used to demand the opposite — two suites, one contract.
	var generator := CombatTestKit.CountingGenerator.new([0.999])
	CombatBand.roll(_tuning, _p_hit(defender, weak), 0.0, 0.0, generator)
	assert_eq(generator.draws, 0, "a saturated hit with no bands spends no draw")
	assert_eq(_p_hit(defender, weak), _p_hit(defender, strong), "landed chance is realm-free")


func test_the_mechanism_sees_the_ladder_gated_base_and_never_the_raw_magnitude() -> void:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 10.0
	var attacker := _attacker_at(&"attacker", &"spirit_sea")
	# A mechanism MUST be bound: S4 is the seam and an unbound attacker is a caller bug
	# `MechanismSlot.of` refuses loudly. This test forgot, so the spine called `resolve`
	# on a null and `seen_base` kept its `-1.0` sentinel — which is a sentinel, so it read
	# as "the mechanism saw nothing" rather than as "the mechanism never ran".
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, CombatTestKit.rng()
	)
	# The technique's OWNING ladder, keyed by realm id (ADR 0055, ADR 0182), which is what
	# S1 reads. This used to read `RealmRate.factor` — the TRAINING rate — and asserted
	# `100.0 * rate`; the rate is a rate of a different quantity, so the ADR 0055 ladder was
	# priced at nothing and a deep technique reached 1.7758x instead of 2.7667x. The expected
	# value is therefore DERIVED through the table rather than pasted.
	var realm := TechniqueMagnitudeTable.factor(attacker.realm())
	assert_almost_eq(mechanism.seen_base, 100.0 * realm, "S1's output, not the authored magnitude")
	assert_ne(mechanism.seen_base, 100.0, "the realm gate really did move it")
	# The teeth: the ladder is not the training rate wearing a new name, and not the raw
	# magnitude either. At `spirit_sea` the authored table reads 1.4203596 where
	# `RealmRate` reads `1.02^10 = 1.1950939`, so a regression back to the rate — or to
	# `pow(TECHNIQUE_STEP, ordinal)`, the index-derived substitute that also used to sit
	# here — fails here instead of agreeing with whatever S1 happens to print.
	assert_ne(
		mechanism.seen_base,
		100.0 * RealmRate.factor(attacker.realm()),
		(
			"S1 is gated by the technique ladder, not by the training rate (realm %s)"
			% attacker.realm()
		)
	)


func test_an_unknown_realm_leaves_the_base_at_the_authored_magnitude() -> void:
	var attacker := CombatTestKit.actor(&"attacker")
	attacker.set_path(PathState.new(&"qi", &"not_a_realm"))
	assert_almost_eq(
		CombatSpine.base_damage(attacker, CombatTestKit.technique(100.0)),
		100.0,
		"the ladder's neutral for an id off the ladder"
	)


# --- 2. S2 before S4 -----------------------------------------------------------


func test_a_miss_never_invokes_the_mechanism() -> void:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 50.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	# `p_hit` at 0.0 is a saturated miss band: `CombatBand.roll` compares `r >= p_land`
	# and every draw is at or above 0.0.
	var band := CombatBand.roll(_tuning, 0.0, 0.0, 0.0, CombatTestKit.CountingGenerator.new([0.5]))
	assert_eq(band.missed, true, "p_hit 0.0 misses")
	assert_eq(mechanism.resolve_calls, 0, "and the mechanism was never asked")


func test_a_landed_hit_invokes_both_seam_stages_exactly_once() -> void:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 50.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var band := CombatBand.roll(_tuning, 1.0, 0.0, 0.0, CombatTestKit.CountingGenerator.new([0.5]))
	assert_eq(band.is_clean(), true, "p_hit 1.0 with no bands is a clean hit")
	assert_eq(mechanism.resolve_calls, 0, "a band roll alone never touches the mechanism")


func test_a_miss_spends_nothing_and_reads_as_empty() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	var target := CombatTestKit.actor(&"target")
	var before := target.resource(&"health").current
	# An empty `p_parry`/`p_block` and a `rng` that always draws below 1.0: `p_hit` at
	# 1.0 is saturated, so no draw is consumed and nothing can miss. To force a miss the
	# spine's own `p_hit` must fall, which it does on `Stat.EVASION`.
	target.stats.add_modifier(StatModifier.new(Stat.EVASION, Stat.Op.FLAT, 1_000_000.0, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, CombatTestKit.rng(7)
	)
	assert_eq(outcome.missed, true, "saturating evasion misses")
	assert_eq(target.resource(&"health").current, before, "and spends nothing")
	assert_eq(outcome.to_dict(), {}, "a miss reads as `{}`")


# --- 3. S4 before S6 -----------------------------------------------------------


func test_the_mechanism_never_sees_crit_as_an_input() -> void:
	# A mechanism that read `ctx.crit` and multiplied by it would produce a crit's worth
	# of damage and then be multiplied AGAIN at S6. This asserts it does not: the amount
	# it produced is readable on the outcome, un-multiplied.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := _critting_actor()
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	var outcome := _resolve_with_a_crit(attacker, target, mechanism)
	assert_eq(outcome.crit, true, "S3 critted")
	assert_almost_eq(
		outcome.proposed_amount(), 40.0, "S4/S5 produced exactly what the mechanism returned"
	)
	var expected := 40.0 * attacker.stats.derived(Stat.CRIT_DAMAGE)
	assert_almost_eq(
		outcome.amount, expected, "S6 multiplied the mechanism's output by CRIT_DAMAGE"
	)


func test_crit_is_resolved_from_crit_chance_and_never_from_crit_damage() -> void:
	# `Stat.CRIT_DAMAGE` has a 1.5 baseline on every actor, so a spine that read it as
	# the CHANCE would crit 150% of the time. `crit` is false on a quiet attacker whose
	# `Stat.CRIT_CHANCE` is 0.0 even though `CRIT_DAMAGE` is 1.5.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	var outcome := _resolve_with_a_crit(attacker, target, mechanism)
	assert_eq(outcome.crit, false, "CRIT_DAMAGE is not a chance")
	assert_almost_eq(outcome.amount, 40.0, "a clean non-crit is the mechanism's amount, unmodified")


# --- 4. S7 before S8, S8 before S9 ---------------------------------------------


func test_reduction_runs_and_then_the_floor_restores_the_chip() -> void:
	# `Stat.DAMAGE_REDUCTION` is FLAT with a `0.0` baseline (ADR 0022), so it is a
	# subtraction. 9.0 on `amp_scale = 10.0` takes the factor to 0.1, which turns 40.0
	# into 4.0 — and 4.0 is above the floor, so the assertion is that the floor did NOT
	# raise it. The reverse ordering (floor, then reduction) is what makes immunity
	# reachable, and `test_combat_immunity.gd` pins that end to end.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 9.0, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(outcome.amount, 4.0, "S7 reduced, and S8's floor did not lift it")
	assert_almost_eq(outcome.proposed_amount(), 40.0, "the mechanism is untouched by S7")


func test_the_floor_runs_after_reduction_not_before_it() -> void:
	# Same setup, but the reduction is total: S7 drives the amount to 0.0 and only S8 can
	# put anything back. If S8 ran first, this would be 0.0.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	target.stats.add_modifier(StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1e9, &"test"))
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(
		outcome.amount, _tuning.min_chip_abs, "S8 restored exactly the floor, after S7"
	)


# --- internals -----------------------------------------------------------------


func _attacker_at(id: StringName, realm: StringName) -> Actor:
	var subject := CombatTestKit.quiet_actor(id)
	subject.set_path(PathState.new(&"qi", realm))
	return subject


## An actor whose `Stat.CRIT_CHANCE` is 1.0 on a FLAT modifier — the only form that can
## move a `0.0`-baseline channel (ADR 0022), and the one `CombatStats.rate_modifier`
## builds for every combat-owned rate.
func _critting_actor() -> Actor:
	var subject := CombatTestKit.actor(&"attacker")
	subject.stats.add_modifier(StatModifier.new(Stat.CRIT_CHANCE, Stat.Op.FLAT, 1.0, &"test"))
	return subject


## Resolve with a generator that crits on the S3 draw. The band is saturated (`p_hit`
## 1.0, no parry, no block) so the FIRST draw is the crit draw and it is consumed.
func _resolve_with_a_crit(
	attacker: Actor, target: Actor, _mechanism: CombatTestKit.FixedMechanism
) -> CombatOutcome:
	return CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, _always_low()
	)


## Draws 0.0 forever: below every band edge and below `Stat.CRIT_CHANCE`, so a crit
## happens exactly when the attacker can crit.
func _always_low() -> CombatTestKit.CountingGenerator:
	return CombatTestKit.CountingGenerator.new([0.0])


## `Stat.EVASION` less `CombatStats.ACCURACY`, on `rate_scale`. Mirrors S2's `p_hit`
## without reaching past the band roll, so this file asserts the property rather than
## the private helper.
func _p_hit(defender: Actor, attacker: Actor) -> float:
	var evasion := maxf(
		0.0, defender.stats.derived(Stat.EVASION) - attacker.stats.derived(CombatStats.ACCURACY)
	)
	return clampf(1.0 - evasion / _tuning.rate_scale, 0.0, 1.0)
