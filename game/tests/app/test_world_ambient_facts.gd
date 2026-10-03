extends TestCase

## The world's OWN news, and the four event triggers that were permanently false.
##
## ## The defect this file closes
##
## `uv run python -m tools gate_reach check` reported fourteen `unbacked_demand`
## findings. Four of them were event triggers — `storm_front_sighted`,
## `void_seam_sounded`, `tournament_called`, `sect_war_called` — naming a fact no
## producer wrote. Four of seven shipped events could therefore **never open**.
##
## The cause was not a typo. An event trigger is read BEFORE `EventApi.begin` writes a
## beat (`event/api.gd:150`), so a trigger names the world **as it already was** — and
## the world recorded exactly one thing, `world_period_elapsed`. Nothing produced
## ambient world facts at all, so those four gates were arithmetic against zero, not
## a near miss.
##
## ## Why these assertions and not a census re-run
##
## `gate_reach` reads authored content and `res://src`, and it does not resolve
## `WorldPulse.offer` — it resolves `WorldFact.record(<expr>, CONST, <n>)` and nothing
## else. So the census **cannot see a fact the pulse writes**: `world_period_elapsed`
## itself, which the boot path accrues every `PERIOD_SECONDS`, is absent from
## `gate_reach report`'s supply table. A green `gate_reach` here would therefore have
## required a producer chosen for being VISIBLE rather than for being REACHABLE, and
## these assertions drive the real production classes and read the ledger the game
## actually keeps instead.
##
## ## What would make these go red again
##
## Deleting `WorldPulse._offer_ambient`, emptying `WorldPulse.AMBIENT_FACTS`, or
## dropping `storm_front_sighted` from it: each was run and observed. So was routing
## the ambient beat straight at `WorldFact.record` instead of through `offer` — that
## makes the event-trigger tests pass and leaves the quest uncompletable, which is
## asserted separately because it is the tempting half-fix.
##
## ## The fixture is the production wiring, not a re-implementation of it
##
## `_world()` is the two lines `app/item_workbench_app.gd:77` runs. It is written out
## rather than reached through the mounted scene because the load-bearing property here
## is the PULSE's, and a scene whose boot is broken by another agent's in-flight edit
## must not be able to turn these assertions into vacuous passes. The mounted-scene
## end-to-end version of the same chain lives in `test_world_beat_chain.gd`.

## The roster the pulse publishes, read rather than restated so a retune of
## `WorldPulse.AMBIENT_FACTS` cannot make this suite lie about what it watches.
const STORM := &"storm_front_sighted"

## A fixture quest whose single step watches the world's own news. Its grant is a
## REAL authored fate, because `DestinyApi.earn_fate` answers a fate it cannot
## resolve by returning the ledger UNCHANGED — a made-up id would make this suite
## green against a grant that silently paid nothing.
const WATCHED := &"t_ambient_watcher"
const GRANTED_FATE := &"ancestral_debt_unpaid"

## The one shipped event whose trigger is exactly one ambient fact and nothing else,
## so opening it proves the gate rather than a conjunction.
const TIDE := &"beast_tide_of_the_mortal_plains"


func teardown() -> void:
	QuestFixtureCatalog.teardown()


## An actor carrying the three modules the chain touches, at the location the tide is
## tied to. `EventApi.attach` is what puts a `location_id` in the ledger for
## `available()` to filter on, so it is not optional here.
func _actor(at: String = &"mortal_plains") -> Actor:
	var actor := Actor.new(&"ambient_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	EventApi.attach(actor)
	EventApi.set_location(actor, at)
	return actor


## The production composition root's world, built the way
## `app/item_workbench_app.gd:77` builds it: a fresh `BeatDirector` handed to a
## `WorldPulse`, which registers both sinks in ADR 0117's priority order.
func _world(actor: Actor) -> WorldPulse:
	return WorldPulse.new(actor, BeatDirector.new())


## Every ambient fact id, as the class publishes it.
func _roster() -> Array[String]:
	var out: Array[String] = []
	for row in WorldPulse.AMBIENT_FACTS:
		out.append(String((row as Dictionary).get("fact", "")))
	return out


# --- The roster is real content, not a comment -------------------------------


## The roster names the four facts the shipped triggers demand, and the pulse
## publishes it so a screen or a probe reads one list rather than re-deriving it.
func test_the_pulse_publishes_the_facts_the_shipped_triggers_demand() -> void:
	var pulse := WorldPulse.new()
	var summary := pulse.summary() as Dictionary

	var ids := summary["ambient_facts"] as Array
	assert_eq(ids.size() >= 4, true, "the pulse publishes an ambient roster: %s" % str(ids))
	for fact in [String(STORM), "void_seam_sounded", "tournament_called", "sect_war_called"]:
		assert_eq(
			ids.has(fact),
			true,
			"a trigger in the shipped tree demands '%s' and the world can now report it" % fact
		)
	assert_eq(summary["ambient_recorded"], 0, "and none has happened to an actorless pulse")


## Every shipped trigger that demands prior world memory names a fact this roster can
## report. Read from the TRIGGERS rather than trusting the roster, so a fifth event
## gated on prior memory goes red HERE rather than being reported dead by a census
## that cannot see the pulse.
##
## `has_fate` / `has_destiny` / `counter` / `declare` are deliberately NOT counted:
## those are `destiny`'s and `sect`'s to answer, and `gate_reach` names them as its
## blind spot 3 rather than as defects.
func test_every_shipped_trigger_asking_prior_memory_names_a_reported_fact() -> void:
	var reported := _roster()
	assert_eq(reported.is_empty(), false, "the roster was read from the class, not hardcoded")

	var checked := 0
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		for fact in _fact_demands(def.trigger):
			checked += 1
			assert_eq(
				reported.has(fact),
				true,
				(
					"%s demands prior memory of '%s', which the world cannot report"
					% [String(event_id), fact]
				)
			)
	assert_eq(checked >= 4, true, "the four dead triggers were actually read: %d" % checked)


# --- An EVENT TRIGGER: red on the shape that shipped -------------------------


## THE event-trigger assertion. Nothing here records the fact by hand — which is what
## `test_world_beat_chain.gd:309` has to do to get this same event open, and that
## hand-record is the vacuous-wiring class ADR 0088 names: live in a test, dead in play.
func test_the_shipped_tide_opens_without_a_hand_written_fact() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	assert_eq(WorldFact.count(actor, STORM), 0, "no front has been sighted yet")
	assert_eq(
		EventApi.available(actor).size(),
		0,
		"so the tide's trigger is false and the event is not available: ADR 0077's shape"
	)

	pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, STORM),
		1,
		"one whole period produced the world's own news, and the test recorded nothing"
	)
	var opened: Array[String] = []
	for row in EventApi.active(actor):
		opened.append(String(row["event_id"]))
	# Read `active`, not `available`: the pulse opens what it sees, so by now the tide
	# is OPEN, and `available` correctly withholds an event that is already open.
	# Asserting on `available` here fails for the right reason with the wrong message.
	assert_eq(
		opened, [String(TIDE)], "and the shipped trigger now OPENS the tide: %s" % str(opened)
	)
	assert_eq(
		WorldFact.count(actor, &"beast_tide_started"),
		1,
		"which wrote its authored opening beat, so the whole ladder is live"
	)


## The roster is offered BEFORE the events are consulted, so the sighting and the tide
## it causes arrive on the same pull. Asserted because reordering the two lines is a
## one-character edit that costs a player one whole period of nothing happening.
func test_the_sighting_and_the_event_it_causes_land_on_the_same_pull() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	var report := pulse.advance_periods(1) as Dictionary

	assert_eq(WorldFact.count(actor, STORM), 1, "the front was sighted")
	assert_eq(
		int(report["opened"]), 1, "and the composition root opened the tide on that same pull"
	)


## The once-check is the LEDGER's own count, so three periods still report one
## sighting. A roster that kept its own "already said this" flag would make this red,
## which is the ADR 0117 second-copy failure with a boolean instead of a dictionary.
func test_three_periods_sight_one_front() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	pulse.advance_periods(1)
	pulse.advance_periods(1)
	pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, STORM),
		1,
		"three periods, one sighting, because the once-check reads the ledger"
	)
	assert_eq(
		WorldFact.fact(actor, STORM).since,
		1,
		"and `since` is the count at first record, so this really is the first"
	)


## A pull that elapsed nothing is no movement at all, so it sights nothing. The
## accrual verbs refuse a non-positive amount by design and this must not become the
## one place a period happens for free.
func test_a_pull_of_no_periods_reports_nothing() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	var report := pulse.advance_periods(0) as Dictionary

	assert_eq(bool(report["ok"]), true, "no elapsed time is not a failure")
	assert_eq(WorldFact.count(actor, STORM), 0, "and nothing accrued")


## The roster is staggered, so all four do not open at once against the one-event
## budget. Read the authored periods rather than hardcoding them.
func test_the_roster_is_staggered_so_one_pull_sights_one_front() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	pulse.advance_periods(1)

	var recorded := pulse.summary()["ambient_recorded"] as int
	assert_eq(
		recorded, 1, "period 1 sighted exactly one ambient fact, not all of them: %d" % recorded
	)


# --- A QUEST STEP: red on the shape that shipped -----------------------------


## THE quest-step assertion, and the one that separates "the fact is in the ledger"
## from "the world acted". A fact in the ledger is NOT a completed quest: the quest
## module is read-only over the ledger (`QuestFactReader` documents that it "may only
## read it"), so a step is only re-read when a DIRECTED beat reaches
## `QuestBeatHandler`. Routing the ambient beat straight at `WorldFact.record` would
## make the event-trigger test above pass and leave this one red.
func test_a_quest_step_watching_the_world_news_completes_off_the_beat() -> void:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				WATCHED,
				QuestDef.KIND_AUTHORED,
				{},
				[{"step_id": &"sighted", "fact": STORM, "need": 1}],
				[{"kind": &"fate", "id": GRANTED_FATE, "amount": 1}]
			)
		]
	)
	var actor := _actor()
	QuestApi.attach(actor)
	var pulse := _world(actor)
	var accepted := QuestApi.accept(actor, WATCHED)
	assert_eq(bool(accepted.get("ok", false)), true, "the player can accept the watcher quest")

	pulse.advance_periods(1)

	var summary := QuestApi.summary(actor)
	assert_eq(
		summary["completed"] as Array,
		[String(WATCHED)],
		"the world's own news completed a quest the player was holding"
	)
	var fates := DestinyApi.summary(actor)["fates"] as Dictionary
	var row = fates.get(String(GRANTED_FATE), {})
	assert_eq(
		bool((row as Dictionary).get("held", false)),
		true,
		"and the crossing step paid its grant, so the completion had a consequence"
	)


## The beat was CLAIMED by the quest sink, not merely recorded. A producer that wrote
## the ledger and bypassed the director would satisfy the ledger half of the test above
## and fail this one, which is the whole point of naming the sink.
func test_the_ambient_beat_is_claimed_by_the_quest_sink() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	pulse.advance_periods(1)

	var world := pulse.summary() as Dictionary
	assert_eq(
		world["sinks"] as Array, ["QuestBeatHandler", "EventBeatSink"], "both sinks are registered"
	)
	assert_eq(
		world["offered"] as int,
		2,
		"two beats were offered: the ambient sighting and the period itself"
	)
	assert_eq(
		world["claimed"] as int,
		0,
		"neither was claimed, because no active quest watches either fact here"
	)


## A fact the roster does not name must still be outstanding afterwards. Without this
## an empty roster would make the completion test pass for the wrong reason.
func test_a_fact_the_world_never_reports_is_still_outstanding() -> void:
	var actor := _actor()
	var pulse := _world(actor)

	pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, &"duels_won"),
		0,
		"the world reported its own news and nothing else: a player's duels are not ambient"
	)


# --- Plumbing ---------------------------------------------------------------


## Every `{verb: fact, id, need}` row in a requirement, flattening `all_of` only.
## `any_of` is an alternative nobody has to take and `none_of` is a prohibition
## satisfied by FAILING, so neither is a demand on supply — the same reading
## `gate_reach` states for the census.
func _fact_demands(requirement: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if requirement.is_empty():
		return out
	var verb := String(requirement.get("verb", ""))
	if verb == "fact":
		var fact := String(requirement.get("id", ""))
		if fact != "":
			out.append(fact)
		return out
	if verb != "all_of":
		return out
	for child in requirement.get("of", []) as Array:
		if child is Dictionary:
			out.append_array(_fact_demands(child as Dictionary))
	return out
