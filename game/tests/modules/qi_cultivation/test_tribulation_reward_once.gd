extends TestCase

## ADR 0041/0061: entering R19 pays a tribulation reward exactly once.
##
## The defect this file pins shut lived in the module, not in core. The fight paid
## its reward when it was resolved, and then the breakthrough that consumed the
## survivor called `actor.tribulation.apply_result(actor, true)` again — so R19
## granted double insight for one fight and stacked two `heavenly_blessing`
## statuses. Core is once-guarded (`Tribulation.apply_result` is the only awarder)
## and the module no longer decides a tribulation at all, so the whole loop is
## driven through the public entry points and the award is counted from outside.
##
## Every preparation below goes through production actions on authored content:
## channel states, the dantian, the pill, progress and comprehension are all earned
## or spent, never written, and `test_full_traversal.gd` is where the same gates are
## proven reachable at all 29 boundaries.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## R19 is the first realm the Immortal tier gate applies to.
const R19_INDEX := 18


func _actor() -> Actor:
	var actor := Actor.new(
		&"qi_trib_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, &"spirit_ascension"))
	actor.meridians.unlock_for_realm(&"spirit_ascension")
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 1024)
	QiTraining.synchronize(actor)
	return actor


func _seed() -> QiRealmSeed:
	return QiRealmSeed.for_realm(&"earth_immortal")


## Bring the actor to the brink of R19 through public actions only.
func _prepare(actor: Actor) -> void:
	var seed := _seed()
	Probe.recover_all(actor)
	assert_eq(Probe.stock(actor, seed.breakthrough_item), true, "pill stocked")
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for R19")
	Probe.recover_all(actor)
	assert_eq(Probe.earn_progress(actor, seed), true, "progress earned")
	assert_eq(Probe.earn_element_mastery(actor, seed), true, "the element gate is earned")
	assert_eq(
		Probe.meditate_to_floor(actor, seed.comprehension_required), true, "comprehension earned"
	)
	assert_eq(Probe.fill_and_refine(actor, seed), true, "dantian prepared")
	Probe.recover_all(actor)
	assert_eq(Probe.fill_and_refine(actor, seed), true, "dantian refilled")
	assert_eq(Probe.stock(actor, seed.breakthrough_item), true, "pill in hand")


## Fight the tribulation for R19 through the production entry points only. The
## gate opens for a DECIDED win (ADR 0041), so the fight has to be resolved as well
## as run, and `resolve_tribulation` is the only thing that pays it.
func _fight(actor: Actor) -> void:
	Probe.fight(actor, Probe.realm_at(R19_INDEX))


func test_the_tribulation_gate_starts_shut_and_the_actor_can_earn_it() -> void:
	var actor := _actor()
	assert_eq(Breakthrough.tribulation_ok(actor, R19_INDEX), false, "the gate starts shut")
	_prepare(actor)
	assert_eq(
		bool(Probe.preview(actor)["can_attempt"]),
		false,
		"and preparation alone does not open it: %s" % str(Probe.preview(actor)["unmet_conditions"])
	)
	_fight(actor)
	assert_eq(Breakthrough.tribulation_ok(actor, R19_INDEX), true, "a decided win opens it")


## The defect. One fight, one award.
##
## The roll is the dantian's (ADR 0051) and a deviation is a legitimate outcome, so
## the advance is retried against a re-prepared actor. What must not vary is the
## AWARD: comprehension is snapshotted immediately before each attempt and compared
## immediately after the one that advanced, so no meditation in between can hide a
## second payment — and a blessing or an essence award is not something preparation
## can produce at all.
func test_entering_r19_pays_the_tribulation_reward_exactly_once() -> void:
	var actor := _actor()
	_prepare(actor)
	_fight(actor)
	var record := actor.tribulation
	assert_ne(record, null, "a tribulation was fought")
	assert_eq(record.outcome, Tribulation.OUTCOME_SURVIVED, "and it was won")
	assert_eq(record.matches_realm(&"earth_immortal"), true, "for this realm")
	assert_eq(actor.statuses.size(), 1, "the fight itself paid exactly one blessing")
	var essence := actor.resource(&"tribulation_essence")
	var awarded := 0.0 if essence == null else essence.current
	assert_eq(awarded > 0.0, true, "and a tribulation essence award")
	var reward := float(record.get_rewards()["insight"])

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var calls := 0
	while calls < 64:
		calls += 1
		before = actor.stats.get_base(Stat.COMPREHENSION)
		if QiBreakthroughTransaction.execute(actor, rng):
			break
		_prepare(actor)
	assert_eq(actor.path(PATH).rank_id, &"earth_immortal", "entered R19")

	# The module must not have decided the fight again on the way in.
	assert_eq(actor.statuses.size(), 1, "entering R19 added no second blessing")
	assert_eq(
		actor.stats.get_base(Stat.COMPREHENSION),
		before,
		"and paid no insight of its own, against a reward of %f" % reward
	)
	var after := actor.resource(&"tribulation_essence")
	assert_eq(0.0 if after == null else after.current, awarded, "and no second essence award")
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "one verdict, still")


## The survivor is spent by the advance, and the advance never races the fight it
## is gated on: the call that advanced found the survivor already there, so the gate
## required an artifact no single call produces.
func test_the_advance_happens_on_a_call_after_the_fight_is_decided() -> void:
	var actor := _actor()
	_prepare(actor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	var calls := 0
	while calls < 64:
		calls += 1
		var was_survivor := Breakthrough.tribulation_ok(actor, R19_INDEX)
		if not was_survivor:
			# Nothing in the module starts a fight, so the player does. That is the
			# whole point: the survivor the gate needs is an artifact of an action
			# outside the advance.
			_fight(actor)
			continue
		if QiBreakthroughTransaction.execute(actor, rng):
			assert_eq(actor.path(PATH).rank_id, &"earth_immortal", "the realm is entered once")
			assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "on a survivor")
			return
		# A refused attempt re-prepared the actor; the fight was not re-decided, so
		# the award cannot have been paid twice.
		assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "still one verdict")
		_prepare(actor)
	assert_eq(false, true, "the loop never advanced: the gate was unreachable")


## A refused attempt costs no pill, because validation runs before anything is
## spent. That is ADR 0044's contract on the transaction and it is what lets a
## player walk the ladder without banking a fortune in refused attempts.
##
## It does mutate the actor in one disclosed way: `face_tribulation` is the first
## thing `execute` does, so an attempt at R19+ fights a wave before validation can
## refuse it (ADR 0061, Consequences). What must stay shut is the gate.
func test_a_refused_attempt_costs_no_pill() -> void:
	var actor := _actor()
	# No preparation at all: nothing is met, so nothing may be spent.
	assert_eq(Probe.stock(actor, _seed().breakthrough_item), true, "pill stocked")
	var held := ItemsApi.inventory(actor).count(_seed().breakthrough_item)
	assert_eq(QiBreakthroughTransaction.execute(actor), false, "refused")
	assert_eq(
		ItemsApi.inventory(actor).count(_seed().breakthrough_item), held, "and it cost nothing"
	)
	assert_eq(actor.path(PATH).rank_id, &"spirit_ascension", "realm unchanged")
	assert_ne(actor.tribulation, null, "the attempt fought a wave before validation refused")
	assert_eq(actor.tribulation.wave, 1, "exactly one wave, not the whole tribulation")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "and the Immortal gate is still shut")
