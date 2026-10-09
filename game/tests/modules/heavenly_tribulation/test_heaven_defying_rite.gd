extends TestCase

## BL-0951 / ADR 0939, S8: the heaven-defying rite — one press, one karmic fight to a
## verdict, mending on a win and scarring on a loss.
##
## The rite borrows the tribulation slot and restores it: a prior proof is never destroyed
## by it, and the rite record can never satisfy a future gate. Both are asserted, not
## described. Rolls are seeded through the same bounded first-draw sweep the tribulation
## suites use, so no assertion is about luck.

const RITE_REALM := &"qi_refining"


func _hero(comprehension: float = 40.0) -> Actor:
	return Actor.new(&"rite_hero", {Stat.COMPREHENSION: comprehension})


func _snapshotted(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"snapshot %s at %f" % [String(realm_id), perfection]
	)


func _snapshot_of(actor: Actor, realm_id: StringName) -> float:
	return FoundationApi.snapshot_for(actor, realm_id)


## A generator whose first draw lands strictly below `share` (a win against it), swept
## over a bounded seed space. Null when no seed in the space does — asserted non-null
## by callers, so a retune that moves endurance fails loudly instead of silently.
func _rng_below(share: float) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if rng.randf() < share:
			rng.seed = seed_value
			return rng
	return null


## A generator whose first draw lands at or above `share` (a loss against it).
func _rng_above(share: float) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if rng.randf() >= share:
			rng.seed = seed_value
			return rng
	return null


func _endurance(actor: Actor, realm_id: StringName) -> float:
	var probe := Tribulation.new()
	probe.start(actor, realm_id)
	return TribulationEndurance.endurance(actor, probe)


func test_a_won_rite_mends_by_the_authored_step() -> void:
	var actor := _hero()
	_snapshotted(actor, RITE_REALM, 0.1)
	var rng := _rng_below(_endurance(actor, RITE_REALM))
	assert_ne(rng, null, "a winning draw exists in the swept space")
	var result := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM, rng)
	assert_eq(bool(result.get("ok", false)), true, "the rite resolves")
	assert_eq(bool(result.get("survived", false)), true, "and it was won")
	var turn: Dictionary = result.get("turn", {})
	assert_eq(bool(turn.get("ok", false)), true, "so the mend lands")
	assert_almost_eq(
		float(turn.get("after", -1.0)),
		0.1 + TribulationFight.RITE_MEND,
		"by exactly the authored step"
	)
	assert_almost_eq(_snapshot_of(actor, RITE_REALM), 0.3, "on the record itself")


func test_a_lost_rite_scars_and_floors_at_zero() -> void:
	var actor := _hero()
	_snapshotted(actor, RITE_REALM, 0.3)
	var rng := _rng_above(_endurance(actor, RITE_REALM))
	assert_ne(rng, null, "a losing draw exists in the swept space")
	var result := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM, rng)
	assert_eq(bool(result.get("ok", false)), true, "the rite resolves")
	assert_eq(bool(result.get("survived", true)), false, "and it was lost")
	var turn: Dictionary = result.get("turn", {})
	assert_eq(bool(turn.get("ok", false)), true, "so the scar lands")
	assert_almost_eq(
		float(turn.get("after", -1.0)),
		0.3 - TribulationFight.RITE_SCAR,
		"deepening the scar by the authored step"
	)
	var ruined := _hero()
	_snapshotted(ruined, RITE_REALM, 0.05)
	var ruin_rng := _rng_above(_endurance(ruined, RITE_REALM))
	assert_ne(ruin_rng, null, "a losing draw exists in the swept space")
	var loss := HeavenlyTribulationApi.defy_heavens(ruined, RITE_REALM, ruin_rng)
	assert_eq(bool(loss.get("ok", false)), true, "the rite resolves")
	var ruin_turn: Dictionary = loss.get("turn", {})
	assert_almost_eq(float(ruin_turn.get("after", -1.0)), 0.0, "floored at zero, never past it")


func test_a_won_rite_stops_at_the_mended_ceiling() -> void:
	var actor := _hero()
	_snapshotted(actor, RITE_REALM, 0.4)
	var rng := _rng_below(_endurance(actor, RITE_REALM))
	assert_ne(rng, null, "a winning draw exists in the swept space")
	var result := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM, rng)
	var turn: Dictionary = result.get("turn", {})
	assert_almost_eq(
		float(turn.get("after", -1.0)),
		FoundationApi.MEND_CAP,
		"the win lifts to the ceiling, not past it"
	)


func test_rite_refusals_are_named() -> void:
	var actor := _hero()
	assert_eq(
		bool(HeavenlyTribulationApi.defy_heavens(null, RITE_REALM).get("ok", true)),
		false,
		"no actor"
	)
	assert_eq(
		bool(HeavenlyTribulationApi.defy_heavens(actor, &"").get("ok", true)), false, "empty realm"
	)
	var bare := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM)
	assert_eq(bool(bare.get("ok", true)), false, "a realm never left")
	assert_eq(String(bare.get("reason", "")).is_empty(), false, "refused by name")
	_snapshotted(actor, RITE_REALM, 0.9)
	var whole := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM)
	assert_eq(bool(whole.get("ok", true)), false, "a realm at the ceiling")
	assert_eq(String(whole.get("reason", "")).is_empty(), false, "refused by name")


func test_a_fight_in_progress_refuses_and_the_slot_is_untouched() -> void:
	var actor := _hero()
	_snapshotted(actor, RITE_REALM, 0.1)
	var live := Tribulation.new()
	live.start(actor, RITE_REALM)
	actor.tribulation = live
	var result := HeavenlyTribulationApi.defy_heavens(actor, RITE_REALM)
	assert_eq(bool(result.get("ok", true)), false, "the live fight refuses the rite")
	assert_eq(actor.tribulation == live, true, "and the slot still holds the live fight")


func test_a_prior_proof_survives_the_rite_and_still_opens_its_gate() -> void:
	var actor := _hero()
	_snapshotted(actor, RITE_REALM, 0.1)
	# A real proof, fought to a verdict through the production driver — a record that
	# merely ran to its last phase without being decided proves nothing (ADR 0041/0061),
	# so there is no shortcut to standing one up.
	var proof := Tribulation.new()
	proof.start(actor, &"earth_immortal")
	actor.tribulation = proof
	var fought := TribulationFight.fight_to_verdict(
		actor, _rng_below(TribulationEndurance.endurance(actor, proof))
	)
	assert_eq(bool(fought.get("decided", false)), true, "the proof fight was decided")
	assert_eq(proof.survived(), true, "a decided proof for the next realm")
	actor.tribulation = proof
	var result := HeavenlyTribulationApi.defy_heavens(
		actor, RITE_REALM, _rng_below(_endurance(actor, RITE_REALM))
	)
	assert_eq(bool(result.get("ok", false)), true, "the rite resolves")
	assert_eq(actor.tribulation == proof, true, "and the slot holds the same proof")
	assert_eq(
		Breakthrough.tribulation_ok(actor, RealmDefaults.ladder().index_of(&"earth_immortal")),
		true,
		"which still opens its gate — the rite manufactures no proof"
	)
