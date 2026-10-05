extends TestCase

## ADR 0117's debt, named at lines 79-84: **`since` survived two normalisers.**
##
## `core/world_fact.gd` owns `actor.module_data["world_facts"]` and emits rows of
## `{count, since}`. `event/EventFacts` shipped a SECOND normaliser over the same key
## emitting `{id, count}` plus a top-level `sequence`, and its own `record`. Two writers
## on one key truncate each other on the way out, silently, and the field that dies is
## the one an "exactly once" gate reads: a fact whose `since` still equals its `count`
## has happened exactly once, so a `WorldFact` write deleting `since` (and an
## `EventFacts` write deleting `count`) turns a live gate into a blind one.
##
## ## What makes this file separate from `test_event.gd`
##
## `test_event.gd` asserts the same round trip THROUGH `EventApi.begin`, which needs
## the authored catalog and a trigger satisfied. This file drives the event module's
## write path directly — `EventBeatWriter`, the ONE writer — with no catalog, no
## location and no trigger. So it isolates the failure: if `since` dies, it died in
## the ledger write, not in the director's stage logic.
##
## ## The direction matters
##
## The defect was SYMMETRIC and the two directions truncate different fields, so both
## are asserted separately. Recording an unrelated event fact must not touch a fact
## another system owns; and a SECOND accrual of the same fact must not move `since`,
## because `since` is the count at FIRST record and a writer that recomputes it each
## time destroys the "has this happened exactly once" question outright.

const FACT := &"t_truncation_subject"
const OTHER := &"t_truncation_neighbour"
const AMOUNT := 3


func setup() -> void:
	pass


func teardown() -> void:
	pass


## An actor with the event module attached and nothing in its ledger. No catalog is
## installed and no location is set, so nothing here can be satisfied by a def that
## happens to be authored in the tree.
func _actor() -> Actor:
	var actor := Actor.new(&"truncation_actor", {})
	EventApi.attach(actor)
	return actor


## The `since` `core` holds for `fact_id`, read back through `WorldFact` — the module
## that owns the field, so a projection that disagrees with it shows up here rather
## than being laundered through the module under test.
func _since(actor: Actor, fact_id: StringName) -> int:
	return WorldFact.fact(actor, fact_id).since


# --- The count at first record -----------------------------------------------


## `since` is written on the first `record` and NEVER moves again. `WorldFact` reads
## it as AFTER the first accrual, so a first record of three is `count == since == 3`
## and the two halves can never disagree. The "has this happened exactly once" gate is
## a comparison of those two numbers, so this is the state the whole file defends.
func test_a_first_record_writes_since_as_the_count_it_reached() -> void:
	var actor := _actor()
	var written := WorldFact.record(actor, FACT, AMOUNT)

	assert_eq(bool(written.get("ok", false)), true, "the record is accepted")
	assert_eq(WorldFact.count(actor, FACT), AMOUNT, "it counted three")
	assert_eq(_since(actor, FACT), AMOUNT, "`since` is the count at first record")
	assert_eq(
		_since(actor, FACT) == WorldFact.count(actor, FACT),
		true,
		"so a fact that has happened once has count == since, which is the gate"
	)


# --- The truncation, from both directions ------------------------------------


## THE defect, direction one: an event beat recording an UNRELATED fact must not
## delete another system's `since`.
##
## While `EventFacts.normalize` emitted rows of `{id, count}` over a ledger whose rows
## are `{count, since}`, any event write rewrote every other row and dropped the
## field. `EventBeatWriter.offer` is the event module's ONE write path, so it is the
## path that carried the defect; the director's stage logic is irrelevant to it.
func test_an_event_beat_does_not_delete_another_facts_since() -> void:
	var actor := _actor()
	WorldFact.record(actor, FACT, 1)
	assert_eq(_since(actor, FACT), 1, "the fact has a `since` before any event runs")

	# A beat about a DIFFERENT fact, offered through the one writer the event module
	# has. `amount: 1` and an occurrence of 1, so the beat id is `neighbour@1`.
	var offered := EventBeatWriter.offer(
		actor, {"fact": OTHER, "amount": 1, "source": "event:t_sink_probe"}, 1
	)

	assert_eq(bool(offered.get("ok", false)), true, "the event beat is accepted")
	assert_eq(
		_since(actor, FACT),
		1,
		"an event beat recording OTHER facts did not delete this row's since"
	)
	assert_eq(
		WorldFact.count(actor, FACT),
		1,
		"and did not change this row's count either - two writers, one monotone count"
	)
	assert_eq(_since(actor, OTHER), 1, "while the event's own fact did get its own since")


## THE defect, direction two: a SECOND accrual of the SAME fact must not advance
## `since`. The old `EventFacts.record` stored `since` as the ledger SEQUENCE at first
## occurrence while `WorldFact` reads it as the COUNT at first record — the same field
## name, two meanings, over one row. A writer that recomputes `since` per accrual makes
## every fact look as though it had just happened for the first time.
func test_a_second_event_beat_does_not_advance_since_on_the_same_fact() -> void:
	var actor := _actor()
	WorldFact.record(actor, FACT, 2)
	assert_eq(_since(actor, FACT), 2, "`since` is 2 after the first record")

	EventBeatWriter.offer(actor, {"fact": FACT, "amount": 5, "source": "event:t_sink_probe"}, 1)

	assert_eq(WorldFact.count(actor, FACT), 7, "the ledger added five to two")
	assert_eq(
		_since(actor, FACT),
		2,
		"`since` is STILL the count at first record - a second writer must not advance it"
	)
	assert_eq(
		_since(actor, FACT) != WorldFact.count(actor, FACT),
		true,
		"so count and since now disagree, which is how the ledger says 'not the first time'"
	)


## Both writers on one key, and the count they both contribute to is ONE number. The
## mirror of direction two: if a projection normalised the other system's rows into a
## different shape, the next read repairs a value instead of counting it, and a repaired
## count is silently wrong rather than loudly missing.
func test_two_writers_contribute_to_one_monotone_count() -> void:
	var actor := _actor()
	WorldFact.record(actor, FACT, 2)
	EventBeatWriter.offer(actor, {"fact": FACT, "amount": 3, "source": "event:t_sink_probe"}, 2)
	WorldFact.record(actor, FACT, 1)

	assert_eq(WorldFact.count(actor, FACT), 6, "2 + 3 + 1 is one count, not three ledgers")
	assert_eq(_since(actor, FACT), 2, "and `since` still names the first total")


## The round trip that fails the moment a SECOND normaliser exists over this key:
## `since` must be inside the payload a save carries, not reconstructed on read. A
## projection that read `since` off a field the writer never stored would pass every
## in-memory assertion above and lose the gate on the first reload.
func test_since_survives_a_json_round_trip_of_the_ledger() -> void:
	var actor := _actor()
	WorldFact.record(actor, FACT, 2)
	EventBeatWriter.offer(actor, {"fact": FACT, "amount": 4, "source": "event:t_sink_probe"}, 2)

	var restored := Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())))

	assert_eq(WorldFact.count(restored, FACT), 6, "the count survives the round trip")
	assert_eq(
		_since(restored, FACT),
		2,
		"and so does `since`, which is the half a second normaliser would have dropped"
	)


## The gate the field exists for, asserted end to end rather than as a pair of
## numbers: a fact whose `since` still equals its `count` has happened exactly once,
## and one whose `since` is behind its `count` has not. `since` is what makes the
## question answerable from ONE row, so a writer that drops it answers "once" for
## every fact and "never" for none.
func test_the_exactly_once_gate_is_answered_from_the_row() -> void:
	var actor := _actor()

	WorldFact.record(actor, FACT, 1)
	assert_eq(
		_since(actor, FACT) == WorldFact.count(actor, FACT),
		true,
		"one accrual of one: this fact has happened exactly once"
	)

	EventBeatWriter.offer(actor, {"fact": FACT, "amount": 1, "source": "event:t_sink_probe"}, 2)

	assert_eq(
		_since(actor, FACT) == WorldFact.count(actor, FACT),
		false,
		"after a second accrual it has not, and that answer comes from `since` alone"
	)
