extends TestCase

## ADR 0878, the refusal pair: a landed parry or block removes a NEUTRAL share of the
## blow (`1.0 - PARRY_COST` / `1.0 - BLOCK_COST`), and the defender's `strength` and the
## attacker's `shred` move it as a flat delta over `rate_scale` — ADR 0877's shape, read
## at S2's aftermath and never inside the band roll.
##
## This suite is the pair's contract: the neutral is what shipped before the pair, parity
## cancels back to it, either direction is reachable, and the removal cap holds.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the neutral, which is the behaviour that shipped before the pair --------------


func test_an_unauthored_parry_keeps_the_neutral_cost() -> void:
	var outcome := _resolve_response(true, 0.0, 0.0)
	assert_eq(outcome.parried, true, "the band parried")
	assert_almost_eq(
		outcome.overflow, 100.0 * CombatSpine.PARRY_COST, "PARRY_COST's neutral reaches health"
	)


func test_an_unauthored_block_keeps_the_neutral_cost() -> void:
	var outcome := _resolve_response(false, 0.0, 0.0)
	assert_eq(outcome.blocked, true, "the band blocked")
	assert_almost_eq(
		outcome.overflow, 100.0 * CombatSpine.BLOCK_COST, "BLOCK_COST's neutral reaches health"
	)


# --- the pair moves it, in both directions, and parity cancels ---------------------


func test_strength_raises_the_removal_to_the_cap() -> void:
	var outcome := _resolve_response(true, _tuning.rate_scale, 0.0)
	assert_almost_eq(
		outcome.overflow,
		100.0 * (1.0 - _tuning.refusal_cap),
		"a full scale of strength reads the removal cap, never immunity"
	)


func test_shred_lowers_the_removal_to_zero() -> void:
	var outcome := _resolve_response(true, 0.0, _tuning.rate_scale)
	assert_almost_eq(outcome.overflow, 100.0, "a full scale of shred takes the response to nothing")


func test_parity_cancels_to_the_neutral() -> void:
	var outcome := _resolve_response(true, _tuning.rate_scale * 0.25, _tuning.rate_scale * 0.25)
	assert_almost_eq(
		outcome.overflow, 100.0 * CombatSpine.PARRY_COST, "equal halves cancel to the neutral"
	)


func test_blocks_pair_moves_the_same_way() -> void:
	var raised := _resolve_response(false, _tuning.rate_scale, 0.0)
	assert_almost_eq(
		raised.overflow, 100.0 * (1.0 - _tuning.refusal_cap), "block strength caps too"
	)
	var shredded := _resolve_response(false, 0.0, _tuning.rate_scale)
	assert_almost_eq(shredded.overflow, 100.0, "and block shred floors it")


# --- internals --------------------------------------------------------------------


## ONE landed hit that was parried (`parry == true`) or blocked. `strength` lands on the
## defender and `shred` on the attacker, both as FLAT modifiers on the ids this case
## names, so a case authors only the half it is about. The draw `0.4` sits inside EITHER
## response band for a `0.5` landed chance, which is what `p_land - removal` thresholds
## leave reachable.
func _resolve_response(parry: bool, strength: float, shred: float) -> CombatOutcome:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	var target := CombatTestKit.actor(&"target")
	var rate_id := CombatStats.PARRY_RATE if parry else CombatStats.BLOCK_RATE
	var strength_id := CombatStats.PARRY_STRENGTH if parry else CombatStats.BLOCK_STRENGTH
	var shred_id := CombatStats.PARRY_SHRED if parry else CombatStats.BLOCK_SHRED
	target.stats.add_modifier(CombatStats.rate_modifier(rate_id, _tuning.rate_scale, &"test"))
	if strength != 0.0:
		target.stats.add_modifier(CombatStats.rate_modifier(strength_id, strength, &"test"))
	if shred != 0.0:
		attacker.stats.add_modifier(CombatStats.rate_modifier(shred_id, shred, &"test"))
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 100.0
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(
		attacker,
		target,
		CombatTestKit.technique(100.0),
		_tuning,
		CombatTestKit.CountingGenerator.new([0.4])
	)
