extends TestCase

## ADR 0114's hand-off, asserted at the quest module's end of it.
##
## The claim under test: a world's interaction drives a quest chain **only**
## because the beat handler claims a beat whose fact an ACTIVE quest watches, and
## it resolves by re-reading the ledger — never by mutating one.

const WATCHED := &"t_watched_road"
const OTHER := &"t_other_road"
const UNWATCHED := &"t_unwatched_fact"
const IDLE := &"t_idle_road"

const FACT := &"t_a_fact"
const OTHER_FACT := &"t_another_fact"
const UNWATCHED_FACT := &"t_never_watched"


func setup() -> void:
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(
					WATCHED,
					QuestDef.KIND_SYSTEMIC,
					{},
					[{"step_id": &"w", "fact": FACT, "need": 2}]
				),
				QuestFixtureCatalog.quest(
					OTHER,
					QuestDef.KIND_EMERGENT,
					{},
					[{"step_id": &"o", "fact": OTHER_FACT, "need": 1}]
				),
				QuestFixtureCatalog.quest(
					IDLE,
					QuestDef.KIND_AUTHORED,
					{},
					[{"step_id": &"i", "fact": UNWATCHED_FACT, "need": 1}]
				),
			]
		)
	)


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


func _beat(fact: StringName, source: String = "combat") -> Dictionary:
	return {"id": "%s@1" % fact, "fact": fact, "amount": 1, "source": source}


# --- Claiming ---------------------------------------------------------------


## The handler claims a beat whose fact an ACTIVE quest is watching. This is the
## property that makes a world's interaction drive a quest chain at all.
func test_a_beat_whose_fact_an_active_quest_watches_is_claimed() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var handler := QuestBeatHandler.new()

	assert_eq(handler.handles(_beat(FACT), actor), true, "a matching beat is claimed")
	assert_eq(handler.watches(actor, FACT), [String(WATCHED)], "and names the quest that claims it")


## A non-matching beat is left for another handler — or recorded unclaimed, which
## ADR 0114 says is correct: a fact that happened is true whether or not a
## handler cared.
func test_a_beat_no_active_quest_watches_is_ignored() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var handler := QuestBeatHandler.new()

	assert_eq(
		handler.handles(_beat(OTHER_FACT), actor), false, "another quest's fact is not claimed"
	)
	assert_eq(
		handler.handles(_beat(UNWATCHED_FACT), actor), false, "an unwatched fact is not claimed"
	)
	assert_eq(
		handler.handles(_beat(FACT, "combat"), QuestFixtureCatalog.hero()),
		false,
		"a beat for an actor with nothing active is not claimed"
	)
	assert_eq(handler.handles(null, actor), false, "a null beat is not claimed")
	assert_eq(handler.handles(_beat(FACT), null), false, "a null actor claims nothing")


## A quest that is merely OFFERED does not claim. Claiming for an unaccepted
## quest would resolve every beat in the game into nothing.
func test_an_offered_but_unaccepted_quest_does_not_claim_its_beat() -> void:
	var actor := QuestFixtureCatalog.hero()
	var handler := QuestBeatHandler.new()
	# `WATCHED` is ungated, so it IS offered...
	assert_eq(handler.handles(_beat(FACT), actor), false, "an unaccepted quest claims nothing")
	var accepted := QuestApi.accept(actor, WATCHED)
	assert_eq(bool(accepted["ok"]), true, "accepting it succeeds")
	assert_eq(handler.handles(_beat(FACT), actor), true, "and now it claims")


## A COMPLETED quest stops claiming. Completion is once; a handler that kept
## re-driving a finished quest would re-run its completion every time a later beat
## happened to name the same fact.
func test_a_completed_quest_stops_claiming_its_beat() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	QuestFixtureCatalog.record(actor, FACT, 2)
	QuestApi.advance(actor, "combat")

	var handler := QuestBeatHandler.new()
	assert_eq(handler.handles(_beat(FACT), actor), false, "a finished quest claims nothing further")
	var outcome := handler.resolve(_beat(FACT), actor)
	assert_eq(String(outcome["reason"]), "not_handled", "and resolving it is refused")


# --- Resolving --------------------------------------------------------------


## Resolving a claimed beat completes the quest whose step crossed the line and
## returns the completion list the director reports.
func test_resolving_a_claimed_beat_returns_the_completion_list() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var handler := QuestBeatHandler.new()

	# Not enough yet: the beat is claimed but nothing completes.
	QuestFixtureCatalog.record(actor, FACT, 1)
	var early := handler.resolve(_beat(FACT, "combat"), actor)
	assert_eq(bool(early["ok"]), true, "a claimed beat resolves")
	assert_eq((early["completed"] as Array).is_empty(), true, "but one of two is not a completion")

	# The world's own systems write the ledger; the second record crosses the line.
	QuestFixtureCatalog.record(actor, FACT, 1)
	var late := handler.resolve(_beat(FACT, "event:duel"), actor)
	assert_eq(late["completed"], [String(WATCHED)], "the crossing completion is reported")
	assert_eq(String(late["source"]), "event:duel", "and the beat's source is carried through")


## A handler NEVER mutates the ledger. The only rows present are the ones the test
## wrote — ADR 0114: "a handler never mutates; it returns a proposal; the
## director applies", and recording is the director's.
func test_resolving_a_beat_never_writes_to_the_fact_ledger() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	QuestFixtureCatalog.record(actor, FACT, 2)
	var before: Dictionary = actor.get_module_data(&"world_facts").duplicate(true)

	QuestBeatHandler.new().resolve(_beat(FACT, "combat"), actor)

	var after: Dictionary = actor.get_module_data(&"world_facts")
	assert_eq(JSON.stringify(after), JSON.stringify(before), "the ledger is untouched by a resolve")


## One beat, two quests watching the same fact: both complete, because the step
## question is asked per quest and the ledger answers it once.
func test_one_beat_completes_every_active_quest_watching_that_fact() -> void:
	var second := QuestFixtureCatalog.quest(
		&"t_second_watcher",
		QuestDef.KIND_EMERGENT,
		{},
		[{"step_id": &"s", "fact": FACT, "need": 1}]
	)
	var existing := QuestCatalog.instance().definition(WATCHED)
	QuestFixtureCatalog.install([existing, second])

	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	QuestApi.accept(actor, &"t_second_watcher")
	QuestFixtureCatalog.record(actor, FACT, 2)

	var outcome := QuestBeatHandler.new().resolve(_beat(FACT, "combat"), actor)
	assert_eq(
		(outcome["completed"] as Array).size(),
		2,
		"both quests watching the fact complete on one beat"
	)


## A beat may arrive as the `WorldBeat` value object ADR 0114 describes rather
## than a plain dictionary. The handler reads both spellings, so the contracts
## agent landing `core/world_beat.gd` changes nothing here.
func test_a_beat_is_read_in_both_the_dictionary_and_the_value_object_shape() -> void:
	var actor := QuestFixtureCatalog.hero()
	QuestApi.accept(actor, WATCHED)
	var handler := QuestBeatHandler.new()

	assert_eq(handler.handles(_beat(FACT), actor), true, "the dictionary shape is read")
	assert_eq(handler.handles({"fact": FACT}, actor), true, "and so is a bare fact key")

	var shaped := Vector4(0.0, 0.0, 0.0, 0.0)
	shaped.set_meta(&"fact", FACT)
	assert_eq(
		handler.handles(shaped, actor), true, "an object carrying a `fact` property is read too"
	)
