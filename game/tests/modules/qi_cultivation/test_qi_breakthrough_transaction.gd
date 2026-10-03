extends TestCase

## ADR 0024/0031: the qi breakthrough transaction is the production entry point
## (`QiCultivationApi.attempt_breakthrough` -> `QiBreakthroughTransaction.execute`),
## so it must itself honour the preview -> validate -> consume -> advance once
## contract. These tests pin that down; an unvalidated transaction let a single
## pill advance two realms with no progress, quality, channels, or tier gates.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


func _actor() -> Actor:
	var actor := Actor.new(&"qi_tx", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 400)
	QiTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	assert_eq(Probe.stock(actor, def_id, 1), true, "authored item %s stocked" % def_id)


func _seed(actor: Actor) -> QiRealmSeed:
	var target := RealmDefaults.ladder().next(actor.path(PATH).rank_id)
	return QiRealmSeed.for_realm(target.id)


## A seeded RNG, so assertions about the *gate* are not about luck. Success and
## failure are both legitimate outcomes; the tests below that care about the
## gate assert the refusal cases, which are deterministic.
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	return rng


## Bring the actor to the brink of the next realm through public actions only, on
## authored content. It used to hand-open and hand-strengthen every channel and to
## mint an `ItemDef` stub, so it proved the transaction against a fixture it had
## built rather than against anything a player can do (ADR 0095).
func _prepare(actor: Actor) -> QiRealmSeed:
	var state := actor.path(PATH)
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := QiRealmSeed.for_realm(target.id)
	Probe.recover_all(actor)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.training_item)
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for %s" % target.id)
	Probe.recover_all(actor)
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.drain(actor, dantian.current(actor))
	dantian.fill(actor, dantian.effective_capacity())
	# The work budget is earned through the public action, not assigned: a fixture
	# that writes `state.progress` proves the transaction against itself.
	assert_eq(Probe.earn_progress(actor, seed), true, "progress earned for %s" % target.id)
	return seed


# --- The transaction validates ------------------------------------------------


func test_execute_refuses_an_unprepared_actor() -> void:
	var actor := _actor()
	# Stocked with pills, so the only thing stopping the advance is validation.
	_stock(actor, _seed(actor).breakthrough_item)
	assert_eq(QiBreakthroughTransaction.execute(actor, _rng()), false, "no advance")
	assert_eq(actor.path(PATH).rank_id, &"qi_refining", "realm unchanged")


func test_facade_advance_refuses_an_unprepared_actor() -> void:
	var actor := _actor()
	_stock(actor, _seed(actor).breakthrough_item)
	assert_eq(QiCultivationApi.attempt_breakthrough(actor), false, "no advance")
	assert_eq(actor.path(PATH).rank_id, &"qi_refining", "realm unchanged")


func test_execute_refuses_when_the_dantian_is_not_full() -> void:
	var actor := _actor()
	_prepare(actor)
	var pool := actor.resource(QiStats.QI)
	pool.current = 0.0
	QiAccess.dantian(actor).damage(actor)
	assert_eq(QiBreakthroughTransaction.execute(actor, _rng()), false, "no advance")
	assert_eq(actor.path(PATH).rank_id, &"qi_refining", "realm unchanged")


func test_execute_refuses_without_the_pill() -> void:
	var actor := _actor()
	_prepare(actor)
	ItemsApi.inventory(actor).clear()
	assert_eq(QiBreakthroughTransaction.execute(actor, _rng()), false, "no advance")
	assert_eq(actor.path(PATH).rank_id, &"qi_refining", "realm unchanged")


## Two calls, one pill, and the first must actually advance for the second to be
## refused. The roll is the dantian's (ADR 0051) and a deviation is a legitimate
## outcome, so the first call is retried against a re-prepared actor until it lands;
## the old pinned roll made seed 0 succeed by luck, and a test that depends on that is
## a test of the seed rather than of the transaction.
func test_execute_never_advances_two_realms_on_one_pill() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var rng := _rng()
	var attempts := 0
	while attempts < 32:
		attempts += 1
		if QiBreakthroughTransaction.execute(actor, rng):
			break
		_prepare(actor)
	var after_first := actor.path(PATH).rank_id
	assert_ne(after_first, &"qi_refining", "the first call advanced (%d attempts)" % attempts)
	assert_ne(
		RealmDefaults.ladder().next(after_first), null, "and there is a realm above it to want"
	)
	# Nothing was prepared for the realm above, and the pill is spent, so the second
	# call cannot advance and cannot spend anything either.
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	QiBreakthroughTransaction.execute(actor, rng)
	assert_eq(actor.path(PATH).rank_id, after_first, "a second call cannot advance")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills,
		"and consumed no second pill"
	)


func test_execute_matches_preview_on_readiness() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var preview := QiBreakthroughTransaction.preview(actor)
	var first := actor.meridians.get_meridian(seed.required_meridians[0])
	assert_eq(
		bool(preview["can_attempt"]),
		true,
		(
			"preview says ready: %s | pill %d | lung %s/%d | progress %.1f/%.1f"
			% [
				str(preview["unmet_conditions"]),
				ItemsApi.inventory(actor).count(seed.breakthrough_item),
				first.state,
				first.refinement,
				actor.path(PATH).progress,
				seed.progress_required,
			]
		)
	)
	var conditions := QiBreakthroughCondition.new()
	var state := actor.path(PATH)
	assert_eq(
		conditions.can_breakthrough(actor, state, {}),
		true,
		"condition agrees with the preview: %s" % str(preview["unmet_conditions"])
	)
