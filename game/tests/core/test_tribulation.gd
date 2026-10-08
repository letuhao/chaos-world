extends TestCase

## ADR 0020: Heavenly Tribulation system tests.


func test_tribulation_start_initializes_state() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 5, 1.5)
	tribulation.start(actor, &"earth_immortal")
	assert_eq(tribulation.phase, Tribulation.WARNING, "starts in warning phase")
	assert_eq(tribulation.wave, 0, "starts at wave 0")
	assert_eq(tribulation.max_waves, 7, "max_waves computed from realm")
	assert_eq(tribulation.difficulty > 0.0, true, "difficulty computed from realm")


# --- Difficulty contract (ADR 0050) --------------------------------------------
# Difficulty is Tribulation's OWN rating: the realm's wave count times the authored
# pressure of the tribulation's own type. It is not a read of any shared power scale.
# These assert the shape of that answer, never a pasted total, so retuning either
# input is a one-number data edit rather than a suite rewrite.


## The whole formula, read back from the two inputs it is built from — times the
## unprepared BASELINE, because BL-0830's ruling gives every legal attempt that much of
## the rating off before any aid (preparation is an input, and its floor is not zero).
func test_difficulty_is_waves_times_type_pressure() -> void:
	var tribulation := Tribulation.new(Tribulation.ELEMENTAL, 3, 1.0)
	tribulation.start(Actor.new(&"hero"), &"earth_immortal")
	assert_eq(
		tribulation.difficulty,
		(
			float(tribulation.max_waves)
			* Tribulation.TYPE_PRESSURE[Tribulation.ELEMENTAL]
			* (1.0 - Tribulation.PREPARATION_BASELINE)
		),
		"waves x pressure, less the unprepared baseline"
	)


## Every one of the six types is authored, and each is harder than the baseline type.
## An unauthored type defaulting to 0.0 would be a free heavenly tribulation.
func test_every_tribulation_type_is_authored_and_ordered() -> void:
	assert_eq(Tribulation.TYPE_PRESSURE.size(), 6, "one pressure per tribulation type")
	for type in Tribulation.TYPE_PRESSURE:
		var tribulation := Tribulation.new(type, 3, 1.0)
		tribulation.start(Actor.new(&"hero"), &"earth_immortal")
		assert_eq(tribulation.difficulty > 0.0, true, "type %s is authored above zero" % type)
		var pressure := (
			tribulation.difficulty
			/ float(tribulation.max_waves)
			/ (1.0 - Tribulation.PREPARATION_BASELINE)
		)
		assert_eq(
			pressure >= Tribulation.TYPE_PRESSURE[Tribulation.LIGHTNING],
			true,
			"type %s is at least baseline pressure" % type
		)


## Deeper on the ladder means a longer tribulation, so difficulty must never fall as
## the realm climbs. Monotone, not strictly: waves are bucketed per four realms.
func test_a_deeper_realm_is_never_an_easier_tribulation() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous := 0.0
	for realm in realms:
		var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
		tribulation.start(Actor.new(&"hero"), realm.id)
		assert_eq(
			tribulation.difficulty >= previous,
			true,
			"realm %s is not easier than the one below it" % realm.id
		)
		previous = tribulation.difficulty


## The no-realm case for a rating that no longer reads the realm's power: an unknown
## realm id must not produce a difficulty of zero.
func test_an_unknown_realm_is_still_a_fight() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(Actor.new(&"hero"), &"not_a_realm")
	assert_eq(tribulation.difficulty > 0.0, true, "unknown realm has a real difficulty")
	assert_eq(tribulation.max_waves, 3, "unknown realm falls back to the floor wave count")


## A typo in the type must not be a free tribulation either.
func test_an_unknown_type_falls_back_to_baseline_pressure() -> void:
	var tribulation := Tribulation.new(&"not_a_type", 3, 1.0)
	tribulation.start(Actor.new(&"hero"), &"earth_immortal")
	var baseline := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	baseline.start(Actor.new(&"hero"), &"earth_immortal")
	assert_eq(tribulation.difficulty, baseline.difficulty, "unknown type is baseline pressure")
	assert_eq(tribulation.difficulty > 0.0, true, "and not a free tribulation")


## Karmic debt still raises the rating. It is an input, not a curve, so it survives the
## ladder's removal untouched.
func test_karmic_debt_raises_difficulty() -> void:
	var clean := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	clean.start(Actor.new(&"hero"), &"earth_immortal")
	var indebted := Actor.new(&"hero")
	indebted.set_relationship(&"rival", -5.0)
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(indebted, &"earth_immortal")
	assert_eq(tribulation.difficulty > clean.difficulty, true, "debt makes it harder")


func test_tribulation_advance_wave_transitions() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.TRIAL, "warning -> trial")
	assert_eq(tribulation.wave, 1, "wave 1")
	tribulation.advance_wave()
	assert_eq(tribulation.wave, 2, "wave 2")
	tribulation.advance_wave()
	assert_eq(tribulation.wave, 3, "wave 3")
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.CLIMAX, "trial -> climax")
	tribulation.advance_wave()
	assert_eq(tribulation.phase, Tribulation.AFTERMATH, "climax -> aftermath")


func test_tribulation_is_complete() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	assert_eq(tribulation.is_complete(), false, "not complete at start")
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.advance_wave()
	assert_eq(tribulation.is_complete(), true, "complete after aftermath")


func test_tribulation_get_rewards() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 2.0)
	var rewards := tribulation.get_rewards()
	assert_eq(rewards.has("tribulation_essence"), true, "has essence")
	assert_eq(rewards.has("blessing"), true, "has blessing")
	assert_eq(rewards.has("insight"), true, "has insight")
	assert_eq(rewards.has("mark"), true, "has mark")
	assert_eq(rewards["tribulation_essence"], 20, "essence scales with difficulty")
	assert_eq(rewards["mark"], 1, "mark is 1")


func test_tribulation_apply_success() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 20.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"earth_immortal")
	actor.tribulation = tribulation
	tribulation.apply_result(actor, true)
	# The verdict is kept on the actor (ADR 0041): clearing it destroyed the
	# only proof the gate was earned, so a survivor vanished on the next save.
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "win recorded")
	assert_eq(actor.resource(&"tribulation_essence") != null, true, "essence resource added")
	assert_eq(actor.has_status(&"heavenly_blessing"), true, "blessing status added")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION) > 20.0, true, "insight boosts comprehension")


func test_tribulation_apply_failure() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 20.0})
	actor.meridians.unlock_for_realm(&"earth_immortal")
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"earth_immortal")
	actor.tribulation = tribulation
	tribulation.apply_result(actor, false)
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_FAILED, "defeat recorded")
	assert_almost_eq(
		actor.stats.get_base(Stat.COMPREHENSION), 15.0, "dao heart damage reduces comprehension"
	)


func test_tribulation_serialization() -> void:
	var tribulation := Tribulation.new(Tribulation.HEART_DEMON, 7, 2.5)
	tribulation.advance_wave()
	tribulation.advance_wave()
	tribulation.preparation = {"formation": 0.3, "pill": 0.2}
	var data := tribulation.to_dict()
	assert_eq(data["type"], "heart_demon", "type serialized")
	assert_eq(data["phase"], "trial", "phase serialized")
	assert_eq(data["wave"], 2, "wave serialized")
	assert_eq(data["max_waves"], 7, "max_waves serialized")
	assert_eq(data["difficulty"], 2.5, "difficulty serialized")
	assert_eq(data["preparation"]["formation"], 0.3, "preparation serialized")
	var restored := Tribulation.from_dict(data)
	assert_eq(restored.type, Tribulation.HEART_DEMON, "type restored")
	assert_eq(restored.phase, Tribulation.TRIAL, "phase restored")
	assert_eq(restored.wave, 2, "wave restored")
	assert_eq(restored.max_waves, 7, "max_waves restored")
	assert_eq(restored.difficulty, 2.5, "difficulty restored")
	assert_eq(restored.preparation["formation"], 0.3, "preparation restored")


func test_tribulation_all_types() -> void:
	var types := [
		Tribulation.LIGHTNING,
		Tribulation.HEART_DEMON,
		Tribulation.KARMIC,
		Tribulation.ELEMENTAL,
		Tribulation.SPATIAL,
		Tribulation.TEMPORAL,
	]
	for t in types:
		var tribulation := Tribulation.new(t, 3, 1.0)
		assert_eq(tribulation.type, t, "type %s set" % t)


# --- Realm binding (ADR 0020) ------------------------------------------------
# A tribulation is fought for one realm, so a survivor unlocks only that gate.


class NeverCondition:
	extends BreakthroughCondition

	func can_breakthrough(_actor: Actor, _state: PathState, _context: Dictionary) -> bool:
		return false


## Drive the phase machine to aftermath, the state a survivor ends in.
func _survive(tribulation: Tribulation) -> void:
	var guard := 0
	while not tribulation.is_complete() and guard < 32:
		tribulation.advance_wave()
		guard += 1


## A tribulation fought AND won for a realm, held by the actor. Finishing the
## phases is not enough: ADR 0041 requires the fight to be decided, because a
## fight that merely ran to its end has not been survived.
func _survivor(actor: Actor, realm_id: StringName) -> Tribulation:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, realm_id)
	_survive(tribulation)
	actor.tribulation = tribulation
	tribulation.apply_result(actor, true)
	return tribulation


func test_tribulation_start_binds_to_realm() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	assert_eq(tribulation.realm_id, &"", "unbound before start")
	tribulation.start(actor, &"earth_immortal")
	assert_eq(tribulation.realm_id, &"earth_immortal", "start binds the realm")


func test_tribulation_matches_only_its_own_realm() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(Actor.new(&"hero"), &"earth_immortal")
	assert_eq(tribulation.matches_realm(&"earth_immortal"), true, "matches its own realm")
	assert_eq(tribulation.matches_realm(&"heaven_immortal"), false, "does not match a higher realm")
	assert_eq(tribulation.matches_realm(&"spirit_ascension"), false, "does not match a lower realm")
	assert_eq(tribulation.matches_realm(&""), false, "matches nothing when asked about no realm")


func test_tribulation_unbound_matches_nothing() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.phase = Tribulation.AFTERMATH
	assert_eq(tribulation.is_complete(), true, "unbound survivor is complete")
	assert_eq(tribulation.matches_realm(&"earth_immortal"), false, "unbound vouches for no realm")


func test_tribulation_serialization_round_trips_realm_id() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"great_luo")
	_survive(tribulation)
	var data := tribulation.to_dict()
	assert_eq(data["realm_id"], "great_luo", "realm_id serialized")
	var restored := Tribulation.from_dict(data)
	assert_eq(restored.realm_id, &"great_luo", "realm_id restored")
	assert_eq(restored.matches_realm(&"great_luo"), true, "restored survivor keeps its binding")
	assert_eq(
		restored.matches_realm(&"earth_immortal"), false, "restored survivor stays realm-bound"
	)


func test_tribulation_legacy_payload_lacks_realm_id() -> void:
	var legacy := {
		"type": "lightning",
		"phase": "aftermath",
		"wave": 3,
		"max_waves": 7,
		"difficulty": 2.5,
		"preparation": {},
	}
	var restored := Tribulation.from_dict(legacy)
	assert_eq(restored.is_complete(), true, "legacy survivor still loads complete")
	assert_eq(restored.realm_id, &"", "legacy payload loads unbound")
	assert_eq(restored.matches_realm(&"earth_immortal"), false, "legacy survivor unlocks nothing")


func test_tribulation_gate_accepts_its_own_realm() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	_survivor(actor, &"earth_immortal")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), true, "earth_immortal gate open")


func test_tribulation_gate_rejects_another_realm() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	_survivor(actor, &"earth_immortal")
	assert_eq(
		Breakthrough.tribulation_ok(actor, 19), false, "one survivor does not open heaven_immortal"
	)
	assert_eq(Breakthrough.tribulation_ok(actor, 27), false, "nor any later realm")


func test_tribulation_gate_rejects_legacy_unbound_survivor() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.from_dict({"phase": "aftermath"})
	actor.tribulation = tribulation
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "legacy survivor opens no gate")


func test_tribulation_gate_rejects_incomplete_and_off_ladder() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.start(actor, &"earth_immortal")
	actor.tribulation = tribulation
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "unfinished tribulation opens nothing")
	_survivor(actor, &"earth_immortal")
	assert_eq(Breakthrough.tribulation_ok(actor, 9999), false, "off-ladder realm opens nothing")


func test_tribulation_gate_below_threshold_ignores_binding() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	assert_eq(Breakthrough.tribulation_ok(actor, 0), true, "mortal tiers need no tribulation")
	assert_eq(Breakthrough.tribulation_ok(actor, 17), true, "spirit tiers need no tribulation")


func test_failed_breakthrough_does_not_reuse_the_survivor() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"mind", &"spirit_ascension"))
	_survivor(actor, &"earth_immortal")
	# The attempt fails on its own condition, so the tribulation is never spent.
	var advanced := Breakthrough.try_advance_with_tribulation(actor, &"mind", NeverCondition.new())
	assert_eq(advanced, false, "attempt failed")
	assert_eq(actor.tribulation != null, true, "failed attempt keeps the tribulation")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), true, "still valid for its own realm")
	# Once the path stands one realm further on, the leftover survivor is stale.
	actor.path(&"mind").rank_id = &"earth_immortal"
	assert_eq(
		Breakthrough.tribulation_ok(actor, 19),
		false,
		"leftover survivor does not unlock an unrelated realm"
	)
	# Re-fighting for the realm being entered is what opens the gate.
	_survivor(actor, &"heaven_immortal")
	assert_eq(Breakthrough.tribulation_ok(actor, 19), true, "re-fought for the target realm")


func test_tribulation_gate_survives_actor_round_trip() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	_survivor(actor, &"heaven_immortal")
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(Breakthrough.tribulation_ok(restored, 19), true, "binding survives a save/load")
	assert_eq(Breakthrough.tribulation_ok(restored, 18), false, "still bound after a save/load")
