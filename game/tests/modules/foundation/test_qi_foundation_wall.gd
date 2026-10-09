extends TestCase

## BL-0951 / ADR 0939: the foundation wall, proven end to end on the qi ladder.
##
## A SLOPPY run — every realm left at depth 0, the legality floor — walks free through
## the realms whose floors are 0 and is REFUSED at the first authored floor it cannot
## clear, by name and one attempt ahead of the wall. The PERFECTED run is
## `test_full_traversal.gd`'s walk, which trains each realm's channels to the cap so
## every departure snapshots at 1.0.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


func _fresh() -> Actor:
	var actor := Actor.new(&"qi_wall", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 400)
	QiTraining.synchronize(actor)
	return actor


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	return rng


## The gate-minimum pre-state (depth 0 at departure), mirrored from
## `test_qi_breakthrough_transaction.gd`'s `_prepare`.
func _prepare(actor: Actor) -> QiRealmSeed:
	var state := actor.path(PATH)
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := QiRealmSeed.for_realm(target.id)
	Probe.recover_all(actor)
	Probe.stock(actor, seed.breakthrough_item, 1)
	Probe.stock(actor, seed.training_item, 1)
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for %s" % target.id)
	Probe.recover_all(actor)
	var dantian := QiTestKit.dantian(actor)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.drain(actor, dantian.current(actor))
	dantian.fill(actor, dantian.effective_capacity())
	assert_eq(Probe.earn_progress(actor, seed), true, "progress earned for %s" % target.id)
	return seed


func _wall_reported(actor: Actor) -> bool:
	var preview := QiBreakthroughTransaction.preview(actor)
	return (preview.get("unmet_conditions", []) as Array).has("foundation_insufficient")


## The wall bites: a run that leaves every realm at depth 0 advances through the free
## realms, is refused at the first authored floor, and the refusal costs nothing — the
## realm stands and the pill in hand is untouched, because the check sits before both.
func test_a_sloppy_run_is_refused_at_the_first_floor_it_cannot_clear() -> void:
	var actor := _fresh()
	var rng := _rng()
	var advances := 0
	var guard := 0
	while guard < 40 and not _wall_reported(actor):
		guard += 1
		_prepare(actor)
		var landed := false
		var tries := 0
		while tries < 32 and not landed:
			tries += 1
			landed = QiBreakthroughTransaction.execute(actor, rng)
			if not landed:
				_prepare(actor)
		assert_eq(landed, true, "breakthrough %d landed" % (advances + 1))
		if landed:
			advances += 1
	var blocked_at := actor.path(PATH).rank_id
	assert_eq(advances >= 1, true, "the free realms are free (%d advanced)" % advances)
	assert_eq(_wall_reported(actor), true, "the wall is reported at %s" % blocked_at)
	var target := RealmDefaults.ladder().next(blocked_at)
	assert_ne(target, null, "there is a realm above the wall")
	var seed := QiRealmSeed.for_realm(target.id)
	Probe.stock(actor, seed.breakthrough_item, 1)
	var pills_before := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	assert_eq(QiBreakthroughTransaction.execute(actor, rng), false, "the transaction refuses")
	assert_eq(actor.path(PATH).rank_id, blocked_at, "and the realm does not move")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills_before,
		"and no pill is spent"
	)
