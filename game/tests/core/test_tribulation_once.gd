extends TestCase

## ADR 0058: a tribulation is decided once, and the gate it opens is entered through
## a production action rather than a test.

## `test_tribulation_fight.gd` covers the fight itself. This file covers the two
## rules that live across the boundary between the fight and the breakthrough that
## spends it: the award is paid exactly once, and the entry point that drives the
## fight is reachable from every path's public action.

## One fight is at most nine waves plus the warning, trial, climax and aftermath
## phases, so twelve advances finish it. The bound names a fight that would stop
## advancing; it is not a budget to spend, and raising it would turn a loud
## failure into a slow one.
const TRIBULATION_BOUND := 16

# --- Fixtures -----------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _actor(comprehension: float = 40.0) -> Actor:
	return Actor.new(&"tribulation_hero", {Stat.COMPREHENSION: comprehension})


func _actor_at(index: int, path_id: StringName = QiPath.PATH_ID) -> Actor:
	var actor := _actor()
	actor.set_path(PathState.new(path_id, _realm_id(index)))
	return actor


## An actor standing one realm below the Immortal tier with its channels unlocked
## and untrained.
func _actor_at_r18(path_id: StringName = QiPath.PATH_ID) -> Actor:
	var actor := _actor_at(17, path_id)
	actor.meridians.unlock_for_realm(_realm_id(17))
	return actor


## A generator whose next draw is below every possible endurance, so the fight is
## won whatever the rating works out at.
func _roll_below_floor() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if rng.randf() < Tribulation.MIN_ENDURANCE:
			rng.seed = seed_value
			return rng
	return null


## Drive the fight to a decided win through `fight_wave`, for the tests that need
## the record decided without the gate in the way.
func _fight_to_completion(actor: Actor, rng: RandomNumberGenerator) -> void:
	Breakthrough.begin_tribulation(actor, 18)
	var guard := 0
	while guard < 64:
		guard += 1
		actor.tribulation.fight_wave(actor, rng)
		if actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED:
			return


# --- The reward is paid once --------------------------------------------------


## The defect this slice exists to kill: `apply_result` had no once-guard, so the
## fight paid its reward and then the breakthrough that consumed the survivor paid
## it again — 70 insight for a 35-insight fight, and two blessings.
func test_a_second_verdict_pays_nothing_again() -> void:
	var actor := _actor_at_r18()
	_fight_to_completion(actor, _roll_below_floor())
	var tribulation := actor.tribulation
	assert_eq(tribulation.survived(), true, "won once")
	var blessings := actor.statuses.size()
	var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	tribulation.apply_result(actor, true)
	assert_eq(actor.statuses.size(), blessings, "no second blessing")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION), comprehension, "no second insight")
	assert_eq(tribulation.survived(), true, "the verdict stands")


## `resolve_tribulation` is the explicit-verdict hook, and ADR 0041 claimed it was
## idempotent. It guarded only on the phases, so a second call re-paid.
func test_resolving_twice_reports_the_same_answer_and_pays_once() -> void:
	var actor := _actor_at_r18()
	Breakthrough.begin_tribulation(actor, 18)
	var waves := 0
	while Breakthrough.advance_tribulation(actor) and waves < TRIBULATION_BOUND:
		waves += 1
	assert_eq(Breakthrough.resolve_tribulation(actor, true), true, "won")
	var blessings := actor.statuses.size()
	assert_eq(Breakthrough.resolve_tribulation(actor, true), true, "still won")
	assert_eq(actor.statuses.size(), blessings, "and still paid once")


## A decided loss is not rewritten by a later call that would have won. Otherwise a
## caller could talk its way out of a tribulation it lost.
func test_a_decided_loss_is_not_rewritten() -> void:
	var actor := _actor_at_r18()
	Breakthrough.begin_tribulation(actor, 18)
	var lost_waves := 0
	while Breakthrough.advance_tribulation(actor) and lost_waves < TRIBULATION_BOUND:
		lost_waves += 1
	assert_eq(Breakthrough.resolve_tribulation(actor, false), false, "lost")
	assert_eq(Breakthrough.resolve_tribulation(actor, true), false, "still lost")
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_FAILED, "the loss stands")
	assert_eq(actor.has_status(&"heavenly_blessing"), false, "no reward")


## `start` resets the verdict. ADR 0041 said it did; the code did not, so a re-used
## record could arrive at the gate already decided.
func test_start_resets_a_decided_record() -> void:
	var actor := _actor_at_r18()
	var tribulation := Tribulation.new(Tribulation.LIGHTNING)
	tribulation.start(actor, &"earth_immortal")
	var fought := 0
	while not tribulation.is_complete() and fought < TRIBULATION_BOUND:
		fought += 1
		tribulation.advance_wave()
	tribulation.apply_result(actor, true)
	assert_eq(tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "won once")
	tribulation.start(actor, &"heaven_immortal")
	assert_eq(tribulation.outcome, Tribulation.OUTCOME_UNRESOLVED, "and undecided again")
	assert_eq(tribulation.survived(), false, "so it vouches for nothing yet")


# --- The production entry point -----------------------------------------------


## The gate is closed on a bare actor at the Immortal tier and open below it. A gate
## a bare actor already passes is not a gate.
func test_the_gate_is_non_trivial_where_it_applies() -> void:
	var actor := _actor_at_r18()
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "R19 needs a fought tribulation")
	assert_eq(Breakthrough.tribulation_ok(actor, 17), true, "R18 needs none")


## The gate is satisfiable from a legal prior state through the production entry
## point: a path at R18, its channels unlocked, and nothing else.
func test_the_gate_is_satisfiable_from_a_bare_actor_at_r18() -> void:
	var actor := _actor_at_r18()
	var rng := _roll_below_floor()
	var guard := 0
	while guard < 64:
		guard += 1
		if Breakthrough.face_tribulation(actor, QiPath.PATH_ID, rng):
			break
	assert_eq(Breakthrough.tribulation_ok(actor, 18), true, "and earned")


## The call that descends a tribulation never also reports the gate open. That is
## what keeps the gate from requiring an artifact the same call produces: the
## survivor a wave won is opened by the *next* attempt.
func test_the_call_that_fights_never_opens_the_gate() -> void:
	var actor := _actor_at_r18()
	var waves := int(Tribulation.WAVES_BY_TIER[RealmDefaults.IMMORTAL]) + 2
	var rng := _roll_below_floor()
	for call_index in waves:
		assert_eq(
			Breakthrough.face_tribulation(actor, QiPath.PATH_ID, rng),
			false,
			"call %d fought, so it reports the gate shut" % (call_index + 1)
		)
	assert_eq(Breakthrough.face_tribulation(actor, QiPath.PATH_ID, rng), true, "the next goes on")


## A mortal path has no tribulation standing in front of it, so the entry point is a
## no-op rather than a fight nobody asked for.
func test_the_entry_point_is_a_no_op_below_the_immortal_tier() -> void:
	var actor := _actor_at(0)
	assert_eq(Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _roll_below_floor()), true, "")
	assert_eq(actor.tribulation, null, "nothing descended")


## One wave per call: the fight is an encounter with turns, not one opaque check.
func test_the_entry_point_fights_exactly_one_wave_per_call() -> void:
	var actor := _actor_at_r18()
	var tribulation := Breakthrough.begin_tribulation(actor, 18)
	var before := tribulation.wave
	Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _roll_below_floor())
	assert_eq(actor.tribulation.wave, before + 1, "one wave")


## Every path's public breakthrough action descends the tribulation. Without these
## three callers R19-R30 is a wall reachable only by a test writing the record.
func test_every_public_breakthrough_action_descends_the_tribulation() -> void:
	var qi_hero := _actor_at_r18(QiPath.PATH_ID)
	QiCultivationApi.attach(qi_hero)
	QiCultivationApi.attempt_breakthrough(qi_hero)
	assert_ne(qi_hero.tribulation, null, "the qi attempt descended a tribulation")
	assert_eq(qi_hero.tribulation.wave, 1, "and fought a wave of it")

	var body_hero := _actor_at_r18(BodyPath.PATH_ID)
	BodyCultivationApi.attach(body_hero)
	BodyCultivationApi.attach_acupoints(body_hero)
	BodyCultivationApi.attempt_breakthrough(body_hero)
	assert_ne(body_hero.tribulation, null, "the body attempt descended a tribulation")

	var mind_hero := _actor_at_r18(MindPath.PATH_ID)
	MindCultivationApi.attach(mind_hero)
	MindCultivationApi.attach_sea(mind_hero)
	MindCultivationApi.try_breakthrough(mind_hero)
	assert_ne(mind_hero.tribulation, null, "the mind attempt descended a tribulation")


## The waves a refused attempt fights are paid for and persisted, so a save mid-fight
## resumes the same fight rather than restarting it.
func test_an_in_progress_fight_survives_a_save() -> void:
	var actor := _actor_at_r18()
	Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _roll_below_floor())
	Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _roll_below_floor())
	var wave := actor.tribulation.wave
	var restored := Actor.from_dict(actor.to_dict())
	assert_ne(restored.tribulation, null, "the fight is on the save")
	assert_eq(restored.tribulation.wave, wave, "and resumes where it stopped")
	assert_eq(Breakthrough.tribulation_ok(restored, 18), false, "an unfinished fight opens nothing")
