extends TestCase

## ADR 0114's director, asserted.
##
## The claims under test, in the order they matter:
##   1. One offered beat reaches exactly ONE decision and is recorded exactly once.
##   2. The ledger is written BEFORE the sinks are asked, because a sink proposes
##      against the ledger and resolve-first decides the crossing step against the
##      count that did not yet include the beat.
##   3. An unclaimed beat is still recorded: a fact that happened is true whether
##      or not a handler cared.
##   4. "Did this already fire" is the CALLER's question, and the report hands the
##      caller the occurrence id it needs to answer it.

const FACT := &"t_a_fact"
const BOAR := &"killed_boar"
const OCCURRENCE := &"killed_boar@3"
const OTHER_OCCURRENCE := &"killed_boar@4"

const WATCHED := &"t_director_road"


## A sink that claims everything and counts what it was asked. Inner class rather
## than a `class_name` in this file: a sink is test scaffolding, and a global name
## for it would make it look like a shipped implementation to the next reader.
class CountingSink:
	extends BeatSink
	var claims := 0
	var resolves := 0
	var declared := ""
	var seen_count := -1

	func _init(label: String = "CountingSink") -> void:
		declared = label

	func handles(_beat: Variant, _context: Variant = null) -> bool:
		claims += 1
		return true

	func resolve(_beat: Variant, context: Variant = null) -> Dictionary:
		resolves += 1
		# What a real sink does: read the ledger to decide. Recording the value it
		# saw is the only way a test can tell WHICH ORDER the director used.
		if context is Actor:
			seen_count = WorldFact.count(context as Actor, FACT)
		return {"claimed": true, "reason": "", "completed": [String(WATCHED)]}


## A sink that declines everything, so a director with no claimant is reachable.
class DeafSink:
	extends BeatSink
	var resolves := 0

	func handles(_beat: Variant, _context: Variant = null) -> bool:
		return false

	func resolve(_beat: Variant, _context: Variant = null) -> Dictionary:
		resolves += 1
		return {"claimed": false, "reason": "unclaimed"}


# --- One beat, one decision, one record --------------------------------------


## THE invariant. Two sinks both claim this beat; the first registered wins and the
## second is never asked to resolve it. A claim is not a veto, and two handlers
## answering one beat is how a reward gets paid twice.
func test_one_beat_is_resolved_by_exactly_one_sink_even_when_several_claim_it() -> void:
	var actor := Actor.new(&"hero")
	var first := CountingSink.new("FirstWriter")
	var second := CountingSink.new("SecondWriter")
	var director := BeatDirector.new()
	director.add_sink(first)
	director.add_sink(second)

	var report := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(first.resolves, 1, "the first claiming sink resolved the beat")
	assert_eq(second.resolves, 0, "and the second was never asked: a claim is not a veto")
	assert_eq(second.claims, 0, "the loop stopped at the winner, so it was not consulted at all")
	var expected := BeatDirector.sink_name(first)
	assert_eq(String(report["claimed_by"]), expected, "and the report names who answered")
	assert_eq(
		expected,
		BeatDirector.sink_name(second),
		"two instances of the same sink share a name, so the name identifies the CLASS"
	)
	assert_ne(String(report["claimed_by"]), "", "and a name is never empty")
	assert_eq(bool(report["claimed"]), true, "the beat is reported claimed")
	assert_eq(WorldFact.count(actor, FACT), 1, "and the ledger recorded it exactly once")


## The same invariant from the other side: no sink claims and the beat is still
## recorded. ADR 0114 draws this as "recording is not dispatching" — a fact that
## happened is true whether or not a handler cared.
func test_an_unclaimed_beat_is_still_recorded_exactly_once() -> void:
	var actor := Actor.new(&"hero")
	var deaf := DeafSink.new()
	var director := BeatDirector.new()
	director.add_sink(deaf)

	var report := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 2, "combat"))

	assert_eq(deaf.resolves, 0, "no sink claimed it, so none resolved it")
	assert_eq(bool(report["claimed"]), false, "the report says so")
	assert_eq(String(report["claimed_by"]), "", "and names nobody")
	assert_eq(
		bool(report["recorded"] if report.has("recorded") else report["ok"]),
		true,
		"it was recorded"
	)
	assert_eq(WorldFact.count(actor, FACT), 2, "the whole amount, once")


## A director with NO sinks at all is a recorder, not a stub — which is what lets
## one subsystem ship before another has a sink.
func test_a_director_with_no_sinks_records_and_reports_so() -> void:
	var actor := Actor.new(&"hero")
	var director := BeatDirector.new()
	assert_eq(director.sink_names(), [], "no sinks, and it says so")

	var report := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(bool(report["ok"]), true, "and a beat still lands")
	assert_eq(WorldFact.count(actor, FACT), 1, "recorded once, unclaimed")
	assert_eq(String(report["beat_id"]), String(OCCURRENCE), "naming the occurrence it was given")


## A sink registered twice is registered once. A duplicate would be a second
## handler answering the same beat, which is the bug the ordering exists to stop.
func test_a_sink_registered_twice_is_still_consulted_once() -> void:
	var actor := Actor.new(&"hero")
	var sink := CountingSink.new()
	var director := BeatDirector.new()
	director.add_sink(sink)
	director.add_sink(sink)

	director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(director.sink_names(), [BeatDirector.sink_name(sink)], "one registration, not two")
	assert_eq(sink.resolves, 1, "and one resolve")


# --- The order: record BEFORE resolve ---------------------------------------


## The order is load-bearing and this is what pins it. A sink decides by reading
## the ledger, so resolve-first would hand it the count from BEFORE the beat — and
## the step that this beat just crossed would not be seen until the next one, or
## ever. The sink reports the count it saw; it must be the post-record count.
func test_the_beat_is_recorded_before_any_sink_is_asked_to_resolve_it() -> void:
	var actor := Actor.new(&"hero")
	var sink := CountingSink.new()
	var director := BeatDirector.new()
	director.add_sink(sink)

	director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(sink.seen_count, 1, "the sink's proposal was computed against the recorded beat")
	assert_eq(WorldFact.count(actor, FACT), 1, "and the ledger agrees")


# --- Refusals name themselves -----------------------------------------------


## Every malformed claim is refused BY NAME, before any sink is consulted and
## before anything is written. A claim that cannot be read is not offered to
## anybody, because a sink handed an unreadable beat would have to guess.
func test_a_malformed_beat_is_refused_by_name_and_writes_nothing() -> void:
	var actor := Actor.new(&"hero")
	var sink := CountingSink.new()
	var director := BeatDirector.new()
	director.add_sink(sink)

	var cases := [
		{"beat": null, "reason": "invalid_beat", "why": "nothing at all"},
		{"beat": "killed_boar@3", "reason": "invalid_beat", "why": "a bare String"},
		{"beat": {}, "reason": "no_occurrence_id", "why": "no id and no fact"},
		{"beat": {"fact": FACT}, "reason": "no_occurrence_id", "why": "a fact with no occurrence"},
		{"beat": {"id": OCCURRENCE}, "reason": "no_fact", "why": "an occurrence with no fact"},
	]
	for entry in cases:
		var report := director.offer(actor, entry["beat"])
		assert_eq(String(report["reason"]), String(entry["reason"]), "%s is refused" % entry["why"])
		assert_eq(bool(report["ok"]), false, "and the refusal is not an ok")
	assert_eq(WorldFact.count(actor, FACT), 0, "no refusal wrote anything")
	assert_eq(sink.claims, 0, "and no refusal consulted a sink")
	assert_eq(sink.resolves, 0, "nor resolved one")


## A non-positive amount is refused here with the cause `WorldFact.record` would
## have refused it with three stages later. A beat claims that something HAPPENED,
## so zero of it is a caller bug, not a rounding.
##
## Reached through a HAND-BUILT beat, because that is the only way:
## `WorldBeat.make` floors the amount at 1 by design and `coerce` runs a dictionary
## through the same factory, so a dictionary claiming `0` arrives as `1`. The floor
## is the right default; this refusal is the backstop for a caller that assigns
## `amount` directly afterwards.
func test_a_non_positive_amount_is_refused_by_name() -> void:
	var actor := Actor.new(&"hero")
	var director := BeatDirector.new()
	var zero := WorldBeat.make(OCCURRENCE, FACT)
	zero.amount = 0

	var report := director.offer(actor, zero)

	assert_eq(String(report["reason"]), "no_amount", "a zero claim is refused")
	assert_eq(WorldFact.count(actor, FACT), 0, "and writes nothing")
	# And the floor is real rather than a coincidence of this test: the dictionary
	# spelling claiming zero is floored, not refused, because `coerce` shares the
	# factory. Two different answers for two different mistakes is the intent.
	var floored := director.offer(actor, {"id": OCCURRENCE, "fact": FACT, "amount": 0})
	assert_eq(String(floored["reason"]), "", "the dictionary spelling is floored, not refused")
	assert_eq(int(floored["amount"]), 1, "and claims one")


## No actor, no ledger to hold the claim. Refused rather than silently dropped, so
## a caller that forgot its owner sees why nothing happened.
func test_a_beat_with_no_owner_is_refused_by_name() -> void:
	var director := BeatDirector.new()
	var report: Dictionary = director.offer(null, WorldBeat.make(OCCURRENCE, FACT))
	assert_eq(String(report["reason"]), "no_actor", "there is nobody whose ledger could hold it")
	assert_eq(bool(report["ok"]), false, "and it is not an ok")


# --- Once is the caller's, and the report has to make that possible ----------


## ADR 0114's once-rule, pinned as what it actually is: **the caller owns it.** A
## monotone ledger can only answer "how many times", so two writers that mint the
## same occurrence id both land, and nothing here catches it. This test asserts
## that plainly rather than leaving it as an unwritten assumption — a director that
## silently deduplicated would be holding a second copy of a truth `WorldFact`
## already owns, and would disagree with the ledger after the first save/load.
func test_two_writers_offering_one_occurrence_both_land_because_once_is_the_callers() -> void:
	var actor := Actor.new(&"hero")
	var director := BeatDirector.new()
	director.add_sink(CountingSink.new())

	var first := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))
	var second := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(bool(first["ok"]), true, "the first offer lands")
	assert_eq(bool(second["ok"]), true, "and so does the second: once is the caller's to own")
	assert_eq(WorldFact.count(actor, FACT), 2, "which is why the count is 2, not 1")
	# What the director DOES owe the caller: the occurrence id it was handed, so
	# the caller can key its own once-check on it before offering.
	assert_eq(String(second["beat_id"]), String(OCCURRENCE), "the occurrence id is in the report")
	assert_eq(
		String(first["beat_id"]), String(second["beat_id"]), "and both offers named the same one"
	)


## A caller that mints a fresh id per occurrence gets exactly the ledger it asked
## for — the other half of the once-rule, and the reason the id is mandatory.
func test_a_caller_minting_one_id_per_occurrence_gets_one_record_each() -> void:
	var actor := Actor.new(&"hero")
	var director := BeatDirector.new()
	director.add_sink(CountingSink.new())

	director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))
	director.offer(actor, WorldBeat.make(OTHER_OCCURRENCE, FACT, 1, "combat"))

	assert_eq(WorldFact.count(actor, FACT), 2, "three and four are two occurrences")
	assert_eq(
		WorldFact.count(actor, OCCURRENCE), 0, "and the ledger keys on the FACT, never the id"
	)


# --- The defect this exists to fix ------------------------------------------


## The end-to-end claim, and the reason the director is not a nice-to-have.
##
## Before it: a beat recorded by one writer moved the shared ledger but reached no
## quest, because the only caller of `QuestApi.advance` in the repository was a
## test. A world event recorded the very fact a quest step watched, and the quest
## did not complete. Here the record and the resolve happen in one place, in that
## order, so the step this beat crosses is seen.
func test_a_beat_recorded_by_the_director_completes_the_quest_whose_step_it_crossed() -> void:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				WATCHED, QuestDef.KIND_AUTHORED, {}, [{"step_id": &"w", "fact": FACT, "need": 1}]
			)
		]
	)
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var director := BeatDirector.new()
	director.add_sink(QuestBeatHandler.new())

	# One beat, one place: recorded first, then resolved against the new count.
	var report := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(bool(report["ok"]), true, "the beat landed")
	assert_eq(String(report["claimed_by"]), "QuestBeatHandler", "the quest sink claimed it")
	assert_eq(WorldFact.count(actor, FACT), 1, "and the fact is in the world's memory")
	assert_eq(
		(report["detail"] as Dictionary).get("completed", []),
		[String(WATCHED)],
		"the crossing completion is reported by the director"
	)
	assert_eq(
		QuestApi.summary(actor)["completed"] as Array,
		[String(WATCHED)],
		"and the quest is completed, once, from a beat nobody else had to call"
	)


## The same moment WITHOUT the quest sink registered: the fact is recorded and the
## quest does not move. This is the before/after in one pair of tests, and it is
## what proves the first one is measuring the wiring rather than the quest module.
func test_the_same_beat_without_a_quest_sink_records_the_fact_and_moves_no_quest() -> void:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				WATCHED, QuestDef.KIND_AUTHORED, {}, [{"step_id": &"w", "fact": FACT, "need": 1}]
			)
		]
	)
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var director := BeatDirector.new()

	var report := director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))

	assert_eq(bool(report["claimed"]), false, "nobody claimed it")
	assert_eq(WorldFact.count(actor, FACT), 1, "but the fact is still recorded")
	assert_eq(
		QuestApi.summary(actor)["completed"] as Array,
		[],
		"and the quest waits, because recording is not dispatching"
	)


## A second beat for a fact the quest already satisfied completes nothing, because
## completion is decided once — the quest module's own guard, reached through the
## director rather than beside it.
func test_a_second_beat_completes_nothing_because_completion_is_once() -> void:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				WATCHED, QuestDef.KIND_AUTHORED, {}, [{"step_id": &"w", "fact": FACT, "need": 1}]
			)
		]
	)
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var director := BeatDirector.new()
	director.add_sink(QuestBeatHandler.new())

	director.offer(actor, WorldBeat.make(OCCURRENCE, FACT, 1, "combat"))
	var second := director.offer(actor, WorldBeat.make(OTHER_OCCURRENCE, FACT, 1, "combat"))

	assert_eq(
		(second["detail"] as Dictionary).get("completed", []),
		[],
		"a later beat for the same fact completes nothing"
	)
	assert_eq(WorldFact.count(actor, FACT), 2, "while the fact itself keeps being counted")


func teardown() -> void:
	QuestFixtureCatalog.teardown()
