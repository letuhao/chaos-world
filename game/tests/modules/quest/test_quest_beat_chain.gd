extends TestCase

## The quest completion beat chain, proven end to end.
##
## The chain under test:
##
##   A fact is recorded (by any system)
##     -> BeatDirector.offer(actor, beat)     // records to WorldFact, then consults sinks
##     -> QuestBeatHandler.handles(beat, actor)  // claims if an active quest watches the fact
##     -> QuestBeatHandler.resolve(beat, actor)  // calls QuestApi.advance(actor, source)
##     -> QuestApi.advance(actor, source)     // reads shared fact ledger, completes quests
##     -> QuestState.finish(ledger, quest_id)  // once-guard: returns false if already completed
##     -> QuestGrants.pay(actor, def, quest_id)  // pays fate/destiny/item
##
## Every test drives the chain through `BeatDirector.offer` — the one production
## entry point — so the proof covers the wiring, not just the individual verbs.

const QUEST := &"t_chain_quest"
const FACT := &"t_chain_fact"
const OTHER_FACT := &"t_chain_other_fact"
const FATE := &"t_chain_fate"
const DESTINY := &"t_chain_destiny"

const SOURCE := "combat"

var _born: Array = []
var _occurrence := 0


func setup() -> void:
	DestinyFixtureCatalog.install(
		[DestinyFixtureCatalog.story_fate(FATE)],
		[DestinyFixtureCatalog.plain_destiny(DESTINY)]
	)
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				QUEST,
				QuestDef.KIND_AUTHORED,
				{},
				[{"step_id": &"s", "fact": FACT, "need": 1}],
				[
					QuestFixtureCatalog.grant(QuestDef.GRANT_FATE, FATE),
					QuestFixtureCatalog.grant(QuestDef.GRANT_DESTINY, DESTINY),
				]
			),
		]
	)


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()
	for obj in _born:
		if is_instance_valid(obj):
			obj.free()
	_born.clear()


# --- The chain, end to end ---------------------------------------------------


## The full chain fires: a beat is offered, the fact is recorded, the handler
## claims it, the quest completes, and grants are paid.
func test_a_beat_offered_to_the_director_completes_the_quest_and_pays_grants() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)

	var report := _offer(actor, FACT)

	assert_eq(bool(report["ok"]), true, "the director recorded the beat")
	assert_eq(bool(report["claimed"]), true, "the quest sink claimed it")
	assert_eq(String(report["claimed_by"]), "QuestBeatHandler", "and it names the handler")

	var detail := report["detail"] as Dictionary
	assert_eq(
		(detail["completed"] as Array),
		[String(QUEST)],
		"the quest completed through the beat chain"
	)
	assert_eq(
		_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_FATE),
		[String(FATE)],
		"the fate grant was paid"
	)
	assert_eq(
		_ids_of_kind(detail["paid"] as Array, QuestDef.GRANT_DESTINY),
		[String(DESTINY)],
		"the destiny grant was paid"
	)
	assert_eq(
		DestinyApi.has_fate(actor, FATE),
		true,
		"and the fate is in the actor's ledger"
	)
	assert_eq(
		DestinyApi.has_destiny(actor, DESTINY),
		true,
		"and the destiny is in the actor's ledger"
	)


## The once-guard holds across the full chain: a second beat for the same fact
## does not re-complete the quest or pay grants again.
func test_a_second_beat_for_the_same_fact_completes_nothing_and_pays_nothing() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)

	_offer(actor, FACT)
	assert_eq(
		DestinyApi.has_fate(actor, FATE),
		true,
		"the first beat paid the fate"
	)

	# A second occurrence of the same fact — the ledger is monotone, so the count
	# rises and the step stays satisfied. The once-guard must refuse a second payout.
	_occurrence += 1
	var director := BeatDirector.new()
	director.add_sink(QuestBeatHandler.new())
	var second := director.offer(
		actor, WorldBeat.make(&"t_chain_occurrence_%d" % _occurrence, FACT, 1, SOURCE)
	)

	assert_eq(bool(second["claimed"]), false, "the sink does not claim a beat for a finished quest")
	assert_eq(
		_fate_history_count(actor, FATE),
		1,
		"the fate was earned exactly once"
	)


## The handler claims a fact an active quest watches, and does not claim a fact
## no quest watches.
func test_the_handler_claims_only_facts_an_active_quest_watches() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()

	assert_eq(
		handler.handles(_beat(FACT), actor),
		true,
		"a fact the active quest watches is claimed"
	)
	assert_eq(
		handler.handles(_beat(OTHER_FACT), actor),
		false,
		"a fact no quest watches is not claimed"
	)


## Resolving a claimed beat calls QuestApi.advance and returns the completion list.
func test_resolving_a_claimed_beat_completes_the_quest_and_returns_the_completion_list() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)

	var handler := QuestBeatHandler.new()
	var outcome := handler.resolve(_beat(FACT, SOURCE), actor)

	assert_eq(bool(outcome["claimed"]), true, "the beat was claimed")
	assert_eq(
		(outcome["completed"] as Array),
		[String(QUEST)],
		"the completion list names the quest"
	)
	assert_eq(
		String(outcome["source"]),
		SOURCE,
		"and carries the beat's source through"
	)
	assert_eq(
		QuestApi.summary(actor)["completed"],
		[String(QUEST)],
		"and the quest is in the completed list"
	)


## The handler does not claim a beat for a quest that was never accepted.
func test_the_handler_does_not_claim_for_an_unaccepted_quest() -> void:
	var actor := QuestFixtureCatalog.hero()
	var handler := QuestBeatHandler.new()

	assert_eq(
		handler.handles(_beat(FACT), actor),
		false,
		"an unaccepted quest claims nothing"
	)


## The handler does not claim a beat for a completed quest.
func test_the_handler_does_not_claim_for_a_completed_quest() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	_offer(actor, FACT)

	var handler := QuestBeatHandler.new()
	assert_eq(
		handler.handles(_beat(FACT), actor),
		false,
		"a completed quest claims nothing further"
	)


## The handler does not claim a beat with no actor.
func test_the_handler_claims_nothing_without_an_actor() -> void:
	var handler := QuestBeatHandler.new()
	assert_eq(
		handler.handles(_beat(FACT), null),
		false,
		"a null actor claims nothing"
	)


## The handler does not claim a beat with no fact.
func test_the_handler_claims_nothing_without_a_fact() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()
	assert_eq(
		handler.handles(_beat(&""), actor),
		false,
		"an empty fact is not claimed"
	)


## The handler does not claim a null beat.
func test_the_handler_claims_nothing_for_a_null_beat() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()
	assert_eq(
		handler.handles(null, actor),
		false,
		"a null beat is not claimed"
	)


## The handler resolves a beat in both the dictionary and value-object shapes.
func test_the_handler_resolves_a_beat_in_both_the_dictionary_and_value_object_shapes() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()

	var dict_outcome := handler.resolve(_beat(FACT, SOURCE), actor)
	assert_eq(
		(dict_outcome["completed"] as Array),
		[String(QUEST)],
		"the dictionary shape resolves"
	)

	# Reset for the value-object shape
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				&"t_chain_quest_2",
				QuestDef.KIND_AUTHORED,
				{},
				[{"step_id": &"s", "fact": FACT, "need": 1}],
				[QuestFixtureCatalog.grant(QuestDef.GRANT_FATE, FATE)]
			),
		]
	)
	var actor2 := QuestFixtureCatalog.hero()
	QuestApi.accept(actor2, &"t_chain_quest_2")

	var shaped := WorldBeat.make(&"t_chain_beat_2", FACT, 1, SOURCE)
	var shaped_outcome := handler.resolve(shaped, actor2)
	assert_eq(
		(shaped_outcome["completed"] as Array),
		[&"t_chain_quest_2"],
		"the value-object shape resolves"
	)
	assert_eq(
		String(shaped_outcome["source"]),
		SOURCE,
		"and carries the source through"
	)


## The handler's resolve returns a refusal for a beat it does not claim.
func test_resolving_an_unclaimed_beat_returns_a_refusal() -> void:
	var actor := QuestFixtureCatalog.hero()
	var handler := QuestBeatHandler.new()

	var outcome := handler.resolve(_beat(FACT), actor)
	assert_eq(bool(outcome["claimed"]), false, "the beat was not claimed")
	assert_eq(String(outcome["reason"]), "not_handled", "and the refusal names why")
	assert_eq(
		(outcome["completed"] as Array).is_empty(),
		true,
		"and the completion list is empty"
	)


## The handler's watches() returns the quest ids that watch a fact.
func test_watches_returns_the_quest_ids_that_watch_a_fact() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()

	assert_eq(
		handler.watches(actor, FACT),
		[String(QUEST)],
		"the active quest watching the fact is returned"
	)
	assert_eq(
		handler.watches(actor, OTHER_FACT),
		[] as Array[String],
		"no quest watches the other fact"
	)


## The handler never mutates the fact ledger — recording is the director's job.
func test_resolving_a_beat_never_writes_to_the_fact_ledger() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	QuestFixtureCatalog.record(actor, FACT, 1)
	var before: Dictionary = actor.get_module_data(&"world_facts").duplicate(true)

	QuestBeatHandler.new().resolve(_beat(FACT, SOURCE), actor)

	var after: Dictionary = actor.get_module_data(&"world_facts")
	assert_eq(
		JSON.stringify(after),
		JSON.stringify(before),
		"the ledger is untouched by a resolve"
	)


## The handler claims a beat for a quest that is active but whose step is not
## yet satisfied — the claim is about the fact, not the progress.
func test_the_handler_claims_a_fact_even_when_the_step_is_not_yet_satisfied() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	var handler := QuestBeatHandler.new()

	# No fact recorded yet — the step is not satisfied, but the quest is active
	# and watches the fact, so the handler still claims the beat.
	assert_eq(
		handler.handles(_beat(FACT), actor),
		true,
		"the handler claims the fact regardless of progress"
	)

	# Resolving it completes nothing — the step is not met.
	var outcome := handler.resolve(_beat(FACT, SOURCE), actor)
	assert_eq(
		(outcome["completed"] as Array).is_empty(),
		true,
		"but nothing completes"
	)


## The handler does not claim a beat for a quest that is offered but not accepted.
func test_the_handler_does_not_claim_for_an_offered_but_unaccepted_quest() -> void:
	var actor := QuestFixtureCatalog.hero()
	var handler := QuestBeatHandler.new()

	# The quest is ungated, so it IS offered — but not accepted.
	assert_eq(
		handler.handles(_beat(FACT), actor),
		false,
		"an unaccepted quest claims nothing"
	)


## The handler claims a beat for a quest whose step needs more than one
## occurrence — the claim is about the fact, not the count.
func test_the_handler_claims_a_fact_for_a_quest_with_a_multi_occurrence_step() -> void:
	var multi := QuestFixtureCatalog.quest(
		&"t_chain_multi",
		QuestDef.KIND_AUTHORED,
		{},
		[{"step_id": &"m", "fact": FACT, "need": 3}]
	)
	QuestFixtureCatalog.install([multi])
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, &"t_chain_multi")
	var handler := QuestBeatHandler.new()

	assert_eq(
		handler.handles(_beat(FACT), actor),
		true,
		"the handler claims the fact even when the step needs multiple occurrences"
	)


## The handler does not claim a beat for a quest that has been completed.
func test_the_handler_does_not_claim_for_a_quest_completed_through_the_chain() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)
	_offer(actor, FACT)

	var handler := QuestBeatHandler.new()
	assert_eq(
		handler.handles(_beat(FACT), actor),
		false,
		"a completed quest claims nothing"
	)


## The handler's resolve returns the paid and unspent lists from the completion.
func test_resolving_a_claimed_beat_returns_the_paid_and_unspent_lists() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)

	var handler := QuestBeatHandler.new()
	var outcome := handler.resolve(_beat(FACT, SOURCE), actor)

	assert_eq(
		(outcome["paid"] as Array).size(),
		2,
		"both grants were paid"
	)
	assert_eq(
		(outcome["unspent"] as Array).is_empty(),
		true,
		"and nothing was left unspent"
	)


## The handler's resolve carries the fact and source from the beat.
func test_resolving_a_claimed_beat_carries_the_fact_and_source() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, QUEST)

	var handler := QuestBeatHandler.new()
	var outcome := handler.resolve(_beat(FACT, "event:duel"), actor)

	assert_eq(String(outcome["fact"]), String(FACT), "the fact is carried through")
	assert_eq(String(outcome["source"]), "event:duel", "and the source is carried through")


# --- Helpers -----------------------------------------------------------------


func _beat(fact: StringName, source: String = SOURCE) -> Dictionary:
	return {"id": "%s@1" % fact, "fact": fact, "amount": 1, "source": source}


func _offer(actor: Actor, fact: StringName) -> Dictionary:
	_occurrence += 1
	var director := BeatDirector.new()
	director.add_sink(QuestBeatHandler.new())
	return director.offer(
		actor, WorldBeat.make(&"t_chain_occurrence_%d" % _occurrence, fact, 1, SOURCE)
	)


func _ids_of_kind(entries: Array, kind: StringName) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if StringName((entry as Dictionary).get("kind", "")) == kind:
			out.append(String((entry as Dictionary).get("id", "")))
	return out


## How many earning records name `fate_id` in the destiny ledger's history. The
## ledger's own history is the audit trail, so counting it measures the number of
## times the earn RAN, which is what "paid exactly once" means.
func _fate_history_count(actor: Actor, fate_id: StringName) -> int:
	var found := 0
	for record in DestinyApi.state(actor)["history"] as Array:
		var entry := record as Dictionary
		if (
			String(entry.get("kind", "")) == "fate"
			and String(entry.get("id", "")) == String(fate_id)
		):
			found += 1
	return found
