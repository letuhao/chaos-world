extends TestCase

## BL-0951 / ADR 0939: the shared foundation record — write-once snapshots, the carried
## aggregate, and the one write the qi path makes at departure.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


## The transaction test's own actor: the qi path attached at R1 with the comprehension
## the authored gate demands. `Probe.fresh_actor` carries comprehension 0.0 — fine for a
## walk fixture, but a breakthrough gate that reads it can never pass.
func _fresh() -> Actor:
	var actor := Actor.new(&"qi_tx", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 400)
	QiTraining.synchronize(actor)
	return actor


## A seeded RNG, so assertions about the GATE are not about luck: the success case below
## retries against a re-prepared actor rather than depending on one seed.
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	return rng


func _stock(actor: Actor, def_id: StringName) -> void:
	assert_eq(Probe.stock(actor, def_id, 1), true, "authored item %s stocked" % def_id)


## The brink of the next realm through public actions only, mirrored from
## `test_qi_breakthrough_transaction.gd` so the integration half drives the real verbs
## rather than a fixture the test built (ADR 0095).
func _prepare(actor: Actor) -> void:
	var state := actor.path(PATH)
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := QiRealmSeed.for_realm(target.id)
	Probe.recover_all(actor)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.training_item)
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for %s" % target.id)
	Probe.recover_all(actor)
	var dantian := QiTestKit.dantian(actor)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.drain(actor, dantian.current(actor))
	dantian.fill(actor, dantian.effective_capacity())
	assert_eq(Probe.earn_progress(actor, seed), true, "progress earned for %s" % target.id)


func _record_of(actor: Actor) -> Dictionary:
	return FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))


func test_a_snapshot_writes_once_and_a_second_write_is_refused() -> void:
	var actor := _fresh()
	var first := FoundationApi.snapshot(actor, &"qi_refining", 0.4)
	assert_eq(bool(first.get("ok", false)), true, "the first write lands")
	assert_eq(float(first.get("perfection", -1.0)), 0.4, "at the authored value")
	var second := FoundationApi.snapshot(actor, &"qi_refining", 0.9)
	assert_eq(bool(second.get("ok", true)), false, "a second write is refused")
	assert_eq(String(second.get("reason", "")), FoundationApi.R_ALREADY_SNAPSHOTTED, "by name")
	assert_eq(
		FoundationRecord.snapshot_for(_record_of(actor), &"qi_refining"),
		0.4,
		"and the first value stands"
	)


func test_snapshots_clamp_and_the_aggregate_is_their_mean() -> void:
	var actor := _fresh()
	FoundationApi.snapshot(actor, &"qi_refining", 5.0)
	FoundationApi.snapshot(actor, &"foundation", -3.0)
	var record := _record_of(actor)
	assert_eq(FoundationRecord.count(record), 2, "two realms left")
	assert_eq(FoundationRecord.snapshot_for(record, &"qi_refining"), 1.0, "clamped up")
	assert_eq(FoundationRecord.snapshot_for(record, &"foundation"), 0.0, "clamped down")
	assert_almost_eq(FoundationRecord.aggregate(record), 0.5, "the mean of the two")


func test_an_empty_record_is_an_empty_state_not_a_zero_actor() -> void:
	var actor := _fresh()
	var record := _record_of(actor)
	assert_eq(FoundationRecord.count(record), 0, "no realms left yet")
	assert_eq(FoundationRecord.aggregate(record), 0.0, "the aggregate is zero")
	assert_eq(
		String(FoundationApi.snapshot(null, &"qi_refining", 0.5).get("reason", "")),
		FoundationApi.R_NO_ACTOR,
		"a null actor is a named refusal"
	)
	assert_eq(
		String(FoundationApi.snapshot(actor, &"", 0.5).get("reason", "")),
		FoundationApi.R_EMPTY_REALM,
		"an empty realm is a named refusal"
	)


## A partial payload (a field added later, garbage in the map) loads with the good rows
## kept and the bad ones dropped, and the version is stamped on the way out.
func test_a_partial_payload_normalizes_rather_than_failing() -> void:
	var record := FoundationRecord.normalize({"snapshots": {"qi_refining": 0.3, "x": "junk"}})
	assert_eq(FoundationRecord.count(record), 1, "the numeric row survives")
	assert_eq(FoundationRecord.snapshot_for(record, &"qi_refining"), 0.3, "at its value")
	assert_eq(int(record.get("version", 0)), FoundationRecord.SCHEMA_VERSION, "versioned")


## The integration half: a SUCCESSFUL qi breakthrough snapshots the realm it left. The
## roll is real (ADR 0051), so a failed attempt is re-prepared and retried; the loop is
## bounded and its counter moves.
func test_a_successful_qi_breakthrough_writes_the_departure_snapshot() -> void:
	var actor := _fresh()
	var realm_id := actor.path(PATH).rank_id
	var rng := _rng()
	var attempts := 0
	while attempts < 32:
		attempts += 1
		_prepare(actor)
		if QiBreakthroughTransaction.execute(actor, rng):
			break
	var advanced := actor.path(PATH).rank_id
	assert_ne(advanced, realm_id, "the breakthrough landed (%d attempts)" % attempts)
	var record := _record_of(actor)
	assert_eq(
		FoundationRecord.has_snapshot(record, realm_id), true, "the realm left is snapshotted"
	)
	var value := FoundationRecord.snapshot_for(record, realm_id)
	assert_eq(value >= 0.0 and value <= 1.0, true, "perfection is a fraction: %f" % value)
