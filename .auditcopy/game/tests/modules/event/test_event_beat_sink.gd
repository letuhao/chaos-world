extends TestCase

## ADR 0114 / 0117 at the `event` module's end of the seam: a beat the AUTHORED world
## is written about is claimed by `event`, and resolving it changes NOTHING.
##
## ## The claim under test
##
## `event` was not on the director at all — `BeatSink` had no implementer in this
## module, so a world event's fact was recorded and nothing asked what it meant.
## This suite asserts the three properties that make the sink honest:
##
##   1. **It claims only authored facts.** A beat naming a fact no `EventDef` mentions
##      is left for another sink or recorded unclaimed (ADR 0117 line 51).
##   2. **It records nothing.** "Record, then resolve" (ADR 0117 line 46) means the
##      ledger already carries the beat, so a resolve that wrote would double-count
##      every beat in the game. This is the assertion that fails if the sink is ever
##      given a `WorldFact.record` call.
##   3. **It does not advance the world.** `EventApi.advance` needs an explicit
##      `periods`; a beat is "a thing happened", not "a period elapsed", so a sink
##      passing `1` would invent the clock ADR 0085 refuses.
##
## ## Why the fixture ids are REAL authored ids
##
## `handles` asks the CONTENT TREE whether it names a fact, so a test that invented its
## own id would assert nothing about the shipped tree. Every fact below is read out of
## `res://data/event/events/beast_tide_of_the_mortal_plains.tres`, which is why the
## ladder cases work: `moving` gates on `beast_tide_moving`, `on_the_plain` fires
## `beast_tide_broken`, and `dispersed` gates on `beast_tide_broken`.

## The event these fixtures open.
const TIDE := &"beast_tide_of_the_mortal_plains"
## `beast_tide_of_the_mortal_plains.on_enter` — fired when the event OPENS.
const FIRED_ON_OPEN := &"beast_tide_started"
## `Stage_moving.on_enter` — fired when the first stage opens.
const FIRED_ON_STAGE := &"beast_tide_moving"
## `Stage_on_the_plain.on_enter` — fired when the SECOND stage opens, and the fact
## `Stage_dispersed.requires` gates on.
const FIRED_ON_SECOND := &"beast_tide_broken"
## `beast_tide_of_the_mortal_plains.trigger` — the fact that opens the event at all.
const TRIGGER_FACT := &"storm_front_sighted"
## An id no `EventDef` in the tree mentions.
const UNNAMED := &"t_no_event_names_this"


func setup() -> void:
	pass


func teardown() -> void:
	pass


## An actor standing on the plains with the modules an event needs attached and its
## trigger satisfied, so `begin` can actually open.
func _actor() -> Actor:
	var actor := Actor.new(&"event_sink_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	NationApi.attach(actor)
	EventApi.attach(actor)
	EventApi.set_location(actor, &"mortal_plains")
	WorldFact.record(actor, TRIGGER_FACT, 1)
	return actor


func _beat(fact: StringName, source: String = "combat") -> Dictionary:
	return {"id": "%s@1" % fact, "fact": fact, "amount": 1, "source": source}


# --- Claiming --------------------------------------------------------------


## The sink claims a beat whose fact an `EventDef` names. This is what puts `event`
## on the director at all: without it a world event's fact is recorded and nobody asks
## what it unblocked.
func test_a_beat_whose_fact_an_event_names_is_claimed() -> void:
	var sink := EventBeatSink.new()

	assert_eq(
		sink.handles(_beat(FIRED_ON_OPEN), _actor()),
		true,
		"a fact an EventDef fires as an opening beat is claimed"
	)
	assert_eq(
		sink.handles(_beat(FIRED_ON_SECOND), _actor()),
		true,
		"so is a fact an EventDef names only as a GATE target, which is the same authored vocabulary"
	)


## A fact no event names belongs to somebody else, or to nobody. Claiming it would
## resolve every beat in the game into this module's report.
func test_a_beat_no_event_names_is_left_alone() -> void:
	var sink := EventBeatSink.new()

	assert_eq(sink.handles(_beat(UNNAMED), _actor()), false, "an unmentioned fact is not claimed")
	assert_eq(sink.handles(null, _actor()), false, "a null beat is not claimed")
	assert_eq(sink.handles({"id": "x@1"}, _actor()), false, "a beat naming no fact is not claimed")
	assert_eq(
		sink.handles("not a beat", _actor()),
		false,
		"a value that is not a beat in either spelling is not claimed"
	)


## `handles` is a CONTENT question, so it does not need an actor. An event is authored
## process-wide; whether an actor's ledger exists cannot change whether the tree names
## the fact. A null context therefore still claims, and `resolve` reports that nobody
## is watching.
func test_the_claim_does_not_depend_on_whose_ledger_it_would_be() -> void:
	var sink := EventBeatSink.new()

	assert_eq(
		sink.handles(_beat(FIRED_ON_OPEN), null),
		true,
		"an authored fact is claimed even for nobody"
	)
	var outcome := sink.resolve(_beat(FIRED_ON_OPEN), null)
	assert_eq(bool(outcome["claimed"]), true, "and resolves as claimed")
	assert_eq(outcome["watching"], [], "while naming nobody as watching")
	assert_eq(int(outcome["count"]), 0, "and a ledger with no owner reads no count")


## The beat arrives as the `WorldBeat` value object ADR 0114 fixes in
## `core/world_beat.gd`, or as the plain dictionary a stage builds. ADR 0117 line 70-73
## makes `WorldBeat.coerce` the one place that spelling is resolved, and this sink is
## the consumer that uses it — so both shapes must reach the same answer.
func test_a_beat_is_read_in_both_the_dictionary_and_the_value_object_shape() -> void:
	var sink := EventBeatSink.new()

	assert_eq(sink.handles(_beat(FIRED_ON_OPEN), _actor()), true, "the dictionary shape is read")
	var shaped := WorldBeat.make(&"beast_tide_started@1", FIRED_ON_OPEN, 1, "combat")
	assert_eq(sink.handles(shaped, _actor()), true, "and so is the WorldBeat value object")
	var outcome := sink.resolve(shaped, _actor())
	assert_eq(String(outcome["source"]), "combat", "its source is carried through, not re-derived")


# --- Resolving -------------------------------------------------------------


## THE property. ADR 0114: "a handler never mutates"; ADR 0117 line 46: the ledger
## already carries the beat when `resolve` runs. A sink that re-recorded would
## double-count every beat in the game, and this suite is what catches it.
func test_resolving_a_beat_writes_nothing_to_the_fact_ledger() -> void:
	var actor := _actor()
	WorldFact.record(actor, FIRED_ON_OPEN, 1)
	var before := JSON.stringify(actor.get_module_data(WorldFact.MODULE_KEY))

	EventBeatSink.new().resolve(_beat(FIRED_ON_OPEN, "event:t_probe"), actor)

	assert_eq(
		JSON.stringify(actor.get_module_data(WorldFact.MODULE_KEY)),
		before,
		"a resolve mutates no ledger row - recording is the director's, at offer"
	)


## Nor may it move the world. `EventApi.advance` takes an explicit `periods` and
## refuses one absent, so a sink that advanced on "a thing happened" would be the timer
## ADR 0085 and DEF-0111 refuse. The period counter is the honest witness.
func test_resolving_a_beat_does_not_advance_the_world() -> void:
	var actor := _actor()
	EventApi.begin(actor, TIDE, 7)
	var opened := int(EventApi.state(actor).get("period", 0))
	assert_eq(opened, 7, "the fixture opened the event at the caller's own period")

	EventBeatSink.new().resolve(_beat(FIRED_ON_OPEN, "event:t_probe"), actor)

	assert_eq(
		int(EventApi.state(actor).get("period", 0)),
		7,
		"the world's period counter is untouched by a beat that something happened"
	)


## `resolve` carries the contract's `claimed` and `reason` (ADR 0117 line 40-43), plus
## JSON-safe detail the director reports verbatim. A sink that could only say "yes"
## would force the director to re-derive the answer from internals it cannot reach.
func test_resolve_carries_claimed_and_reason_plus_reportable_detail() -> void:
	var actor := _actor()
	WorldFact.record(actor, FIRED_ON_OPEN, 1)

	var claimed := EventBeatSink.new().resolve(_beat(FIRED_ON_OPEN, "combat"), actor)
	assert_eq(bool(claimed["claimed"]), true, "an authored beat is claimed")
	assert_eq(String(claimed["reason"]), "", "and carries the reason key as an empty string")
	assert_eq(String(claimed["fact"]), String(FIRED_ON_OPEN), "the fact is named for the report")
	assert_eq(
		int(claimed["count"]), 1, "the count is the ledger's, read AFTER the director's write"
	)
	assert_eq(int(claimed["since"]), 1, "and `since`, which is what a once-gate reads")
	assert_eq(claimed["satisfied"], [], "no open gate is satisfied, so no stage is reported")

	var declined := EventBeatSink.new().resolve(_beat(UNNAMED), actor)
	assert_eq(bool(declined["claimed"]), false, "a beat this sink does not handle is not claimed")
	assert_eq(String(declined["reason"]), "not_handled", "with the reason the quest sink also uses")


## The report a director CAN act on. The tide's first stage is `moving`, so the
## `on_the_plain` stage is next — and its `requires` names `beast_tide_moving`. Once
## that fact is in the ledger the gate passes, and the sink reports the stage it
## unblocked.
##
## This is the ordering ADR 0117 line 46-49 is about, read from the other side: the
## beat is already recorded by the time `resolve` runs, so the gate is decided against
## a count that INCLUDES it. Resolving first would report nothing and the stage would
## open a beat late.
func test_a_beat_the_directors_record_reported_by_resolve_unblocks_the_next_stage() -> void:
	var actor := _actor()
	EventApi.begin(actor, TIDE)
	assert_eq(
		EventBeatSink.new().watches(actor, FIRED_ON_STAGE),
		[String(TIDE)],
		"the open tide watches the fact its next stage gates on"
	)
	# `begin` already fired `Stage_moving.on_enter`, so the gate is satisfied...
	assert_eq(
		bool(EventGate.evaluate(actor, {"verb": &"fact", "id": FIRED_ON_STAGE, "need": 1})["ok"]),
		true,
		"and the authored gate passes against the ledger the director just wrote to"
	)
	# ...and the sink names the stage, having recorded nothing itself.
	var outcome := EventBeatSink.new().resolve(_beat(FIRED_ON_STAGE), actor)
	assert_eq(
		outcome["satisfied"],
		[{"event_id": String(TIDE), "stage_id": "on_the_plain"}],
		"the beat reports the next stage whose gate it satisfied"
	)
	assert_eq(
		int(outcome["since"]),
		1,
		"`since` is the count at first record, so the report says this is the first time"
	)


## A CLOSED event stops being watched. A resolved event's ladder is finished, and a
## sink that kept naming it would report stages the world has already walked past.
##
## ## **FIVE pulls, and the arithmetic is the contract's, not a convenience.**
## `advance` states two rules that together fix the count (`event/api.gd`, `advance`):
##
##   1. **A stage holds for `duration_periods` WHOLE periods and the NEXT pull is what
##      moves it.** `held <= duration` holds; `held > duration` advances. That is what
##      keeps an authored `0` ("hold for no time at all") distinguishable from an
##      authored `1`, which is the boundary
##      `EventStageDef.duration_periods` is written around.
##   2. **One event, at most one stage, per period** — the loop's own stated reason is
##      that "an event whose every stage holds for zero periods would otherwise clear
##      its whole ladder in a single pull".
##
## The tide's authored ladder is `[moving(1), on_the_plain(1), dispersed(0)]`, so:
##
##   p1 - `moving` holds (held 1 <= 1)
##   p2 - `moving` moves; `on_the_plain` opens, its beats fire, held resets to 0
##   p3 - `on_the_plain` holds (held 1 <= 1)
##   p4 - `on_the_plain` moves; `dispersed` (the final stage) OPENS, held resets to 0
##   p5 - `dispersed` holds nothing (held 1 > 0); it is final, so it RESOLVES
##
## **Rule 2 is why `dispersed` does not resolve on p4.** The pull that REACHES the
## final stage is the same pull that counts its first held period, so the resolution
## lands on the pull after it. This suite used to walk `stage_count() + 1`, which
## stopped one short: `dispersed` had opened but not yet resolved, the event was
## still `active`, and the assertion below was reporting on its own fixture rather
## than on its claim. The same five-pull arithmetic is what
## `test_a_zero_period_stage_resolves_at_the_next_pull_and_not_before` (`test_event.gd`)
## walks for the auction's `[lots_read(1), bids_open(1), hammer(0)]`.
##
## The count is DERIVED from the def's own durations below — `sum(duration + 1)`, one
## pull to REACH each stage and one to resolve the last — rather than typed as a
## literal, so a re-authored ladder cannot leave this suite walking a number the
## content no longer means.
func test_a_resolved_event_is_no_longer_watched() -> void:
	var actor := _actor()
	EventApi.begin(actor, TIDE)
	# One pull per authored stage to REACH it, plus one to resolve the last one.
	var def := EventCatalog.instance().event_definition(TIDE)
	assert_ne(def, null, "the tide this suite drives is in the catalog")
	assert_eq(def.stage_at(0).duration_periods, 1, "and its ladder is the authored one")
	assert_eq(def.stage_count(), 3, "moving -> on_the_plain -> dispersed")
	var pulls := 0
	for index in def.stage_count():
		pulls += def.stage_at(index).duration_periods + 1
	EventApi.advance(actor, pulls)
	assert_eq(
		EventApi.active(actor).size(),
		0,
		"the tide resolved and left `active` - the fixture really is closed"
	)

	assert_eq(
		EventBeatSink.new().watches(actor, FIRED_ON_SECOND),
		[],
		"a resolved event is not watching anything further"
	)
	var outcome := EventBeatSink.new().resolve(_beat(FIRED_ON_SECOND), actor)
	assert_eq(
		bool(outcome["claimed"]), true, "but the beat is still claimed - the fact is authored"
	)
	assert_eq(outcome["satisfied"], [], "while reporting no stage it unblocked")


## Every reported value is primitives-only. The detail is COPIED into a payload that
## travels into logs and UI summaries, so a `Resource`, an `Actor` or a callable in
## here would be smuggled into a save-shaped dictionary.
func test_the_reported_detail_is_primitives_only() -> void:
	var actor := _actor()
	var outcome := EventBeatSink.new().resolve(_beat(FIRED_ON_OPEN), actor)

	const PRIMITIVES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_DICTIONARY, TYPE_ARRAY]
	for key in outcome.keys():
		assert_eq(
			typeof(outcome[key]) in PRIMITIVES,
			true,
			"outcome key '%s' is a primitives-only value" % key
		)
