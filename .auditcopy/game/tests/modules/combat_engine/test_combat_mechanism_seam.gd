extends TestCase

## The seam (ADR 0067): `contracts/damage_mechanism.gd` is a two-virtual contract reached
## by component id, and there is NO `if/else on path_id` anywhere in `modules/combat/`.
##
## ADR 0067 states the proof: "Invariant to test: no `if/else on path_id` anywhere in
## `modules/combat/`, proven by swapping the stub for qi — a one-line `app/` change,
## zero combat edits." This file is the mechanical half of that proof and it needs no qi,
## body or mind to exist: three STUB mechanisms with distinct returns, driven through the
## IDENTICAL spine code, must produce three distinct numbers. If any shared stage had a
## per-path branch, the three would not be a function of the mechanism alone.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- three mechanisms, one spine -----------------------------------------------


func test_three_stub_mechanisms_produce_three_distinct_numbers() -> void:
	var amounts := [10.0, 25.0, 80.0]
	var results: Array[float] = []
	for value in amounts:
		results.append(_resolve_with(value).amount)
	assert_almost_eq(results[0], 10.0, "the first mechanism's number")
	assert_almost_eq(results[1], 25.0, "the second mechanism's number")
	assert_almost_eq(results[2], 80.0, "the third mechanism's number")
	assert_ne(results[0], results[1], "and they really are three, not one")
	assert_ne(results[1], results[2], "each is distinct")


func test_the_identical_request_through_the_identical_code_is_the_mechanisms_and_nothing_else(
) -> void:
	# Same attacker shape, same target shape, same technique, same null rng — the ONLY
	# difference between the two resolves is which mechanism is bound.
	var first := _resolve_with(7.5)
	var second := _resolve_with(60.0)
	assert_almost_eq(first.base, second.base, "S1 is the same for both")
	assert_almost_eq(first.overflow, 7.5, "the first mechanism's amount is what reached health")
	assert_almost_eq(second.overflow, 60.0, "the second mechanism's amount is what reached health")


func test_both_seam_stages_are_called_in_order_for_every_mechanism() -> void:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 30.0
	var attacker := _attacker_for(mechanism)
	CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_eq(mechanism.resolve_calls, 1, "S4 resolve, exactly once")
	assert_eq(mechanism.mitigate_calls, 1, "S5 mitigate, exactly once")


# --- a mechanism is not optional -----------------------------------------------


func test_an_unbound_attacker_has_no_mechanism_to_read() -> void:
	var bare := CombatTestKit.actor(&"bare")
	assert_eq(MechanismSlot.has_mechanism(bare), false, "genuinely unbound")
	assert_eq(MechanismSlot.peek(bare), null, "and the quiet read agrees")


func test_binding_twice_replaces_rather_than_accumulates() -> void:
	# One actor fights one way, so a second binding is a re-attachment (an item swap, a
	# path change) and not a stack. Re-binding must be what the spine reads. The two
	# mechanisms carry DIFFERENT amounts because `FixedMechanism.new()` defaults to
	# `0.0`: two zero-amount mechanisms cannot tell "the second one ran" from "the first
	# one ran" from "neither ran", and the assertion this used to make -- that a pair of
	# default mechanisms produces 25.0 -- was unreachable for any implementation.
	var attacker := CombatTestKit.actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	var replacement := CombatTestKit.FixedMechanism.new()
	replacement.amount = 25.0
	MechanismSlot.bind(attacker, replacement)
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(outcome.overflow, 25.0, "the SECOND binding is the one that ran")
	assert_eq(replacement.resolve_calls, 1, "and it is the one that ran S4")
	assert_eq(replacement.mitigate_calls, 1, "and S5")


func test_the_slot_id_is_one_string_and_the_spine_reads_no_other() -> void:
	assert_eq(MechanismSlot.COMPONENT_ID, &"damage_mechanism", "ADR 0067's component id")
	var attacker := CombatTestKit.actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	assert_ne(attacker.component(&"damage_mechanism"), null, "and it lands in that slot")


func test_clearing_restores_the_unbound_state() -> void:
	var attacker := CombatTestKit.actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	MechanismSlot.clear(attacker)
	assert_eq(MechanismSlot.has_mechanism(attacker), false, "a path change can unbind")


# --- a mechanism that declines --------------------------------------------------


func test_a_mechanism_may_decline_a_hit_it_does_not_recognise() -> void:
	# ADR 0069: "qi never returns 0.0 for a landed hit", but ADR 0067's contract says
	# "Returns 0.0 for a hit it declines" and qi may decline a hit it has no elemental
	# reading for. That is the seam's contract, not the element table's — so the spine
	# must pass a decline through and still spend the chip floor, not treat it as a miss.
	var declined := CombatTestKit.FixedMechanism.new()
	declined.amount = 0.0
	var attacker := _attacker_for(declined)
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_eq(outcome.missed, false, "a declined hit is still a landed hit")
	assert_almost_eq(
		outcome.amount, _tuning.min_chip_abs, "and still pays the chip floor, so it is not free"
	)


func test_a_mechanism_returning_nothing_survives_the_mitigate_fallback() -> void:
	# A mechanism written against the seam may return the inherited
	# `DamageProposal.NONE` from `resolve`; the spine must still call `mitigate` on it
	# rather than skipping S5 and leaving a shared stage unrun.
	var declining := DecliningMechanism.new()
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, declining)
	CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_eq(declining.mitigate_calls, 1, "S5 ran on the inherited NONE")


# --- effects are the path's own state writes -----------------------------------


func test_a_mechanisms_effects_survive_the_spine_untouched() -> void:
	# ADR 0067: "`effects[]` are the path's own state writes, applied AFTER HP." The
	# spine's job is to CARRY them, not to interpret them — mind returns `amount 0.0`
	# plus turbulence/clarity/awareness effects, and the spine must not have an opinion.
	#
	# The count is NOT 1 and must not be: S12 (ADR 0087) appends its own
	# `status_application` entry to the same array, which is why the assertion is "the
	# mechanism's entry is still there, verbatim, at the head" rather than a size. A size
	# assertion here could only ever have passed before S12 landed.
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 0.0
	mechanism.effects = [{"kind": &"turbulence", "value": 0.4}] as Array[Dictionary]
	var attacker := _attacker_for(mechanism)
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	var effects := outcome.effects()
	assert_eq(effects.size() >= 1, true, "the effect survived the eleven stages")
	assert_eq(String((effects[0] as Dictionary)["kind"]), "turbulence", "verbatim")
	assert_almost_eq(float((effects[0] as Dictionary)["value"]), 0.4, "and at its own magnitude")
	# Everything S12 added rides beside it and carries the status kind, so the spine's
	# append is asserted rather than merely tolerated.
	for index in range(1, effects.size()):
		assert_eq(
			String((effects[index] as Dictionary)["kind"]),
			String(StatusApply.EFFECT_KIND),
			"entry %d is S12's, not a second mechanism write" % index
		)
	assert_almost_eq(outcome.amount, _tuning.min_chip_abs, "and a mind-style hit still chips")


# --- internals -----------------------------------------------------------------


func _attacker_for(mechanism: DamageMechanism) -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	return attacker


func _resolve_with(amount: float) -> CombatOutcome:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = amount
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)


## A mechanism that returns nothing from `resolve`, so the spine's `null` fallback has to
## call `mitigate` with the inherited `DamageProposal.NONE`.
class DecliningMechanism:
	extends DamageMechanism

	var mitigate_calls: int = 0

	func resolve(_ctx: AttackContext) -> DamageProposal:
		return null

	func mitigate(_ctx: AttackContext, proposal: DamageProposal) -> DamageProposal:
		mitigate_calls += 1
		return proposal
