extends TestCase

## ADR 0020/0032: a tribulation is a playable, resumable challenge, not an inert
## record. These tests use only the production entry points on `Breakthrough` --
## the same calls a panel or a gameplay action makes -- so a gate that can never
## be satisfied by real play fails here.
##
## The rule under test is not "does Tribulation work" (test_tribulation.gd covers
## the phase machine) but "can a survivor actually be earned in production, and
## does it unlock exactly one gate".

const R18 := 17
const R19 := 18
const R20 := 19


## The ladder is keyed by realm id, but the tests think in indices. Resolving
## through the array keeps the two vocabularies from being mixed up.
func _realm_id(index: int) -> StringName:
	var realms := RealmDefaults.ladder().realms()
	return realms[index].id


func _actor_at(index: int, path_id: StringName = &"qi") -> Actor:
	var actor := Actor.new(&"tribulation_hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(path_id, _realm_id(index)))
	return actor


func _fight_to_completion(actor: Actor) -> void:
	var guard := 0
	while Breakthrough.advance_tribulation(actor) and guard < 64:
		guard += 1


## A mortal path needs no tribulation, so nothing is created. Starting one anyway
## would put a fight in the actor's way that no gate will ever ask for.
func test_no_tribulation_below_the_immortal_threshold() -> void:
	var actor := _actor_at(R18 - 1)
	assert_eq(Breakthrough.begin_tribulation(actor, R18 - 1), null, "no tribulation offered")
	assert_eq(actor.tribulation, null, "actor untouched")


func test_begin_binds_to_the_realm_being_entered() -> void:
	var actor := _actor_at(R18)
	var tribulation := Breakthrough.begin_tribulation(actor, R19)
	assert_ne(tribulation, null, "a tribulation was started")
	assert_eq(actor.tribulation, tribulation, "stored on the actor")
	assert_eq(tribulation.realm_id, _realm_id(R19), "bound to the realm being entered")
	assert_eq(tribulation.phase, Tribulation.WARNING, "starts in warning")


## The gate is closed until the fight is actually survived. This is the defect
## DEF-0052 described: previously nothing outside a test could produce a
## survivor, so R19+ was unreachable in real play.
func test_gate_stays_closed_until_survived() -> void:
	var actor := _actor_at(R18)
	assert_eq(Breakthrough.tribulation_ok(actor, R19), false, "no tribulation yet")
	Breakthrough.begin_tribulation(actor, R19)
	assert_eq(Breakthrough.tribulation_ok(actor, R19), false, "started but not survived")
	_fight_to_completion(actor)
	# Reaching the last phase is not survival: the outcome is explicit.
	assert_eq(Breakthrough.tribulation_ok(actor, R19), false, "complete but unresolved")
	assert_eq(Breakthrough.resolve_tribulation(actor, true), true, "survived")
	# The decided record stays on the actor: it is the only proof this realm's
	# gate was earned, so clearing it would re-close the gate on the next save.
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "win recorded")


## One survivor unlocks exactly one gate (ADR 0032). Earning R19's tribulation
## must not carry over into R20, which has its own.
func test_one_survivor_unlocks_only_its_own_realm() -> void:
	var actor := _actor_at(R18)
	Breakthrough.begin_tribulation(actor, R19)
	_fight_to_completion(actor)
	Breakthrough.resolve_tribulation(actor, true)
	assert_eq(Breakthrough.tribulation_ok(actor, R19), true, "R19 gate open")
	assert_eq(Breakthrough.tribulation_ok(actor, R20), false, "R20 gate still closed")


## Re-beginning an unfinished tribulation would discard the waves already
## survived, letting a player reset a losing fight for free. The in-progress
## record is returned untouched instead.
func test_begin_does_not_restart_an_unfinished_fight() -> void:
	var actor := _actor_at(R18)
	var first := Breakthrough.begin_tribulation(actor, R19)
	Breakthrough.advance_tribulation(actor)
	var waves_survived := first.wave
	assert_ne(Breakthrough.begin_tribulation(actor, R19), null, "returns the live fight")
	assert_eq(actor.tribulation.wave, waves_survived, "progress preserved")


func test_failure_leaves_the_gate_closed_and_grants_nothing() -> void:
	var actor := _actor_at(R18)
	Breakthrough.begin_tribulation(actor, R19)
	_fight_to_completion(actor)
	assert_eq(Breakthrough.resolve_tribulation(actor, false), false, "defeat reported")
	assert_eq(Breakthrough.tribulation_ok(actor, R19), false, "gate still closed")
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_FAILED, "defeat recorded")


## Walking away from a fight you cannot win must cost nothing and gain nothing:
## no rewards, no completion. This is what makes cancelling distinct from losing.
func test_cancel_forfeits_without_resolving() -> void:
	var actor := _actor_at(R18)
	Breakthrough.begin_tribulation(actor, R19)
	_fight_to_completion(actor)
	Breakthrough.cancel_tribulation(actor)
	assert_eq(actor.tribulation, null, "gone")
	assert_eq(Breakthrough.tribulation_ok(actor, R19), false, "no survivor from a walkout")


func test_advance_and_resolve_are_no_ops_without_a_tribulation() -> void:
	var actor := _actor_at(R18)
	assert_eq(Breakthrough.advance_tribulation(actor), false, "nothing to advance")
	assert_eq(Breakthrough.resolve_tribulation(actor, true), false, "nothing to resolve")


## A survivor must survive the save round trip, or a long fight is lost to a
## crash. The attempt rides on the actor, so this follows from serialization
## rather than from any special case.
func test_survivor_survives_a_save_round_trip() -> void:
	var actor := _actor_at(R18)
	Breakthrough.begin_tribulation(actor, R19)
	_fight_to_completion(actor)
	Breakthrough.resolve_tribulation(actor, true)

	var restored := Actor.from_dict(actor.to_dict())
	restored.set_path(PathState.new(&"qi", _realm_id(R18)))
	assert_ne(restored.tribulation, null, "tribulation restored")
	assert_eq(restored.tribulation.is_complete(), true, "still complete after reload")
	assert_eq(restored.tribulation.realm_id, _realm_id(R19), "still bound")
	assert_eq(restored.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "outcome persisted")
	assert_eq(Breakthrough.tribulation_ok(restored, R19), true, "gate open after reload")
	assert_eq(Breakthrough.tribulation_ok(restored, R20), false, "R20 still closed")


## An in-progress fight is resumable, which is the "playable resumable
## challenge" the objective named.
func test_in_progress_fight_is_resumable_after_reload() -> void:
	var actor := _actor_at(R18)
	Breakthrough.begin_tribulation(actor, R19)
	Breakthrough.advance_tribulation(actor)
	Breakthrough.advance_tribulation(actor)
	var wave_before := actor.tribulation.wave

	var restored := Actor.from_dict(actor.to_dict())
	restored.set_path(PathState.new(&"qi", _realm_id(R18)))
	assert_ne(restored.tribulation, null, "fight restored")
	assert_eq(restored.tribulation.wave, wave_before, "resumes where it stopped")
	_fight_to_completion(restored)
	Breakthrough.resolve_tribulation(restored, true)
	assert_eq(Breakthrough.tribulation_ok(restored, R19), true, "finishable after reload")
