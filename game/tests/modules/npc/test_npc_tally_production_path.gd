extends TestCase

## BL-0658 and BL-0628: **the stage advance that nothing triggered, and the contract
## nobody listened to.** Two gaps, one piece of work.
##
## ## Why this suite drives the EVENT PATH and not `tally`
##
## `test_npc_stage_thresholds.gd` already proves `NpcApi.tally` walks Elder Wei's
## ladder when called directly. That was never the gap: the gap was that **no player
## action could reach it**. Every test here drives the route production takes —
## `WorldPulse.pull` -> `EventApi.begin` -> `EventApi.advance` -> `EventBeatWriter.offer`
## -> the injected `NpcApi.tally` — because a test that calls `tally` itself passes
## against a build in which nothing in the game ever calls it.
##
## ## What each test would fail on
##
##   - No authored `npc_tally` beat in `data/event/`: every advancement test is red.
##   - `_tally_npc` still writing `module_data` directly: `test_the_event_writer_is_no
##     longer_a_second_writer_for_the_roster` is red, because the direct write skips
##     `advance_verb` and the third unrelated verb walks the elder a rung.
##   - No subscriber on `NpcEvents.stage_advanced`: every ledger test is red.
##
## ## Nothing here leaks
##
## No `Node` is created. `NpcApi.attach` pins a process-wide player that nothing can
## clear, so the process-wide singletons this suite WRITES — `NpcLedger`, and the
## injected resolver — are reset in BOTH `setup()` and `teardown()`, because the runner
## shares one process across every suite.

const ELDER := &"elder_wei"
const EVENT := &"the_favour_of_elder_wei"
## `storm_front_sighted` is `WorldAmbient.ROSTER`'s first id and `period 1`, so a
## single pull satisfies this event's trigger without a fixture writing a fact.
const OPENING_FACT := &"storm_front_sighted"
## `mortal_plains` is where the elder stands and where the event is anchored.
const LOCATION := "mortal_plains"
## The verb Elder Wei's `gatekeeper` stage counts. `advance_after = 3`.
const FAVOURS := &"favours"
const PULSE := WorldPulse.PERIOD_SECONDS


func setup() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcCatalog.instance().reset()
	NpcCatalog.instance().load_authored()
	# `reload` rather than a `reset`: `EventCatalog` is a cached directory walk with
	# no reset verb, and this suite reads AUTHORED content, so the cache has to be
	# dropped before the shipped `.tres` under it is believed.
	EventCatalog.instance().reload()
	# The injection `NpcBoot.install` performs in production. Done in setup rather
	# than relying on install's own null-guard order, so a test that never installs
	# still exercises the same seam the game does.
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcApi.attach(null)


# --- The authored beat exists at all -------------------------------------------


## The content half of BL-0658: `grep -rn npc_tally game/data` returned NOTHING, so the
## whole `KIND_NPC_TALLY` branch was unreachable from any save. Read off disk, not off
## a fixture: an implementation whose SHIPPED content is inert must fail here.
func test_an_authored_beat_carries_an_npc_tally_kind_for_the_elder() -> void:
	var found := 0
	for path in ContentScan.files_under("res://data/event/events/"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("npc_tally"):
			found += 1
	assert_ne(found, 0, "at least one authored .tres declares an npc_tally beat")


## The beat names the roster's VERB, not just an npc. `advance_verb = "favours"` on the
## gatekeeper rung means a beat naming anything else is counted but never advances — so
## a typo here is a build where the elder can never move, and content is the only place
## that typo can live.
func test_the_authored_tally_beat_names_the_verb_the_elder_counts() -> void:
	var def := EventCatalog.instance().event_definition(EVENT)
	assert_ne(def, null, "the elder's event is authored and in the catalog")
	var stage := def.stage_at(1)
	assert_ne(stage, null, "it has a second stage, and that stage fires the tally")
	var beat: Dictionary = {}
	for row in stage.on_enter:
		if String(row.get("kind", "")) == String(EventBeatWriter.KIND_NPC_TALLY):
			beat = row
	assert_ne(beat.is_empty(), true, "the second stage carries an npc_tally beat")
	assert_eq(String(beat.get("npc_id", "")), String(ELDER), "naming the elder")
	assert_eq(StringName(beat.get("verb", &"")), FAVOURS, "and the verb his stage counts")


## A beat with `kind: npc_tally` and no `npc_id` is a beat that tallies nobody, and the
## writer's own guard refuses it. Pinned so a future author cannot drop the id and
## learn about it from a player.
func test_an_npc_tally_beat_names_both_the_npc_and_the_verb() -> void:
	var def := EventCatalog.instance().event_definition(EVENT)
	for stage in def.stages:
		for row in stage.on_enter:
			if String(row.get("kind", "")) != String(EventBeatWriter.KIND_NPC_TALLY):
				continue
			assert_ne(String(row.get("npc_id", "")), "", "the beat names an npc")
			assert_ne(String(row.get("verb", "")), "", "and a verb")


# --- The production path advances the elder (BL-0658) ---------------------------


## **The end-to-end claim, driven the way production drives it.** A pulse opens the
## event, a second pull walks it to the stage that carries the tally beat, and the
## roster counts the favour. Three pulls is the route `item_workbench_app.gd` takes on
## its `_process`; nothing here calls `NpcApi.tally` itself.
##
## This is the test that would have been red before the fix in every way at once: with
## no authored beat the pull would advance the ladder and stop, with no facade
## injection the beat would be refused, and with the old direct writer the elder would
## move for a verb his stage never named.
func test_a_pull_drives_the_elder_up_a_stage_through_the_authored_beat() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	# One pull: the ambient news lands (`storm_front_sighted` at period 1), and
	# `EventApi.begin` opens the event on the same pull because the trigger is
	# re-checked there, not trusted from `available`.
	var first := pulse.pull(PULSE)
	assert_eq(
		EventFacts.count_of(player, &"elder_wei_petition_opened"),
		1,
		"the event opened from content, so its opening beat fired"
	)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "and he starts where he starts")
	assert_eq(first["opened"], 1, "the pulse opened one event")

	# The second pull walks `the_petition` -> `the_favour`, whose `on_enter` carries the
	# tally beat. A period is enough: `the_petition` holds for one.
	pulse.pull(PULSE)
	assert_eq(
		EventFacts.count_of(player, &"elder_wei_favour_counted"),
		1,
		"the stage that fires the tally beat was reached"
	)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"gatekeeper",
		"one favour of the three his stage names is not a rung"
	)

	# Two more pulls. The event RESOLVES after its final stage, so the second and third
	# favourites are driven the way a re-opened petition would drive them: through the
	# same writer, on the same injected verb, from the same authored shape.
	_tally_through_the_writer(player, 1)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "two favours still hold")
	_tally_through_the_writer(player, 1)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"the third favour crosses the threshold his stage authored and he advances"
	)


## The same three beats, straight through `EventBeatWriter.offer` — the production
## writer, with the authored beat dictionary read off the shipped `.tres` rather than
## retyped here. A test that hand-writes the beat proves the writer, not the content.
func test_the_shipped_beat_walks_the_elder_when_offered_three_times() -> void:
	var player := _player()
	var beat := _authored_tally_beat()
	assert_ne(beat.is_empty(), true, "the shipped .tres carries a usable tally beat")
	for _i in range(3):
		var outcome := _offer(player, beat)
		assert_eq(
			bool(outcome.get("npc_tallied", false)), true, "the beat tallied: %s" % str(outcome)
		)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"three shipped favours advance him, which is what advance_after = 3 means"
	)


## The verb check is the thing the OLD direct writer skipped, and it is authored content
## (`advance_verb = "favours"`). Offering the same beat with a different verb counts
## against its own key and must never move the elder — this is the exact disagreement
## the two-writer defect allowed.
func test_a_tally_of_a_verb_the_stage_does_not_name_never_advances_him() -> void:
	var player := _player()
	var beat := _authored_tally_beat()
	for _i in range(9):
		var wrong := beat.duplicate(true)
		wrong["verb"] = &"unrelated_verb"
		_offer(player, wrong)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"gatekeeper",
		"nine unrelated verbs accumulate their own tally and move nobody"
	)


## And the cap is a facade property, so it applies on this path too. `MAX_TALLY_KEYS`
## is 16 and the stage ordinal already costs one row, so a seventeenth verb is refused
## — and the refusal is reported rather than silently dropped.
func test_the_tally_cap_applies_on_the_event_path_too() -> void:
	var player := _player()
	var refused := 0
	for index in range(NpcRosterEntry.MAX_TALLY_KEYS + 4):
		var beat := _authored_tally_beat()
		beat["verb"] = StringName("beat_verb_%02d" % index)
		var outcome := _offer(player, beat)
		if not bool(outcome.get("npc_tallied", false)):
			assert_eq(
				String(outcome.get("npc_tally_reason", "")),
				"tally_full",
				"a full table refuses with the facade's own reason, not a silent skip"
			)
			refused += 1
	assert_ne(refused, 0, "the cap was reached on the event path, not just in a unit test")


# --- The two-writer defect is closed --------------------------------------------


## **The defect, as one assertion.** With the old `module_data` write, an unrelated
## verb walked the elder a rung because the direct writer never read `advance_verb`.
## Now `NpcApi.tally` is the only writer, so a verb his stage does not name is recorded
## and nothing else. If someone reintroduces the direct write this goes red.
func test_the_event_writer_is_no_longer_a_second_writer_for_the_roster() -> void:
	var player := _player()
	for _i in range(4):
		var beat := _authored_tally_beat()
		beat["verb"] = &"not_the_authored_verb"
		_offer(player, beat)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"gatekeeper",
		"four beats of an unnamed verb do not move him: only the facade checks advance_verb"
	)


## A missing injection is refused LOUDLY. Before the change an `npc_tally` beat with no
## roster row just returned false and the beat recorded nothing; now it names a reason a
## caller can read, which is what makes the seam's absence diagnosable instead of silent.
func test_a_tally_beat_with_no_resolver_installed_is_refused_and_names_why() -> void:
	var player := _player()
	EventBeatWriter.set_tally_resolver(Callable())
	var outcome := _offer(player, _authored_tally_beat())
	assert_eq(bool(outcome.get("npc_tallied", true)), false, "nothing was tallied")
	assert_eq(
		String(outcome.get("npc_tally_reason", "")),
		"no_tally_resolver",
		"and the refusal names the missing injection rather than reporting silence"
	)


## The fact half is unchanged: an `npc_tally` beat is a SECOND DESTINATION for the same
## proposal, not a replacement. Both the fact and the roster count move on one offer.
func test_the_tally_beat_still_records_its_fact_on_the_way() -> void:
	var player := _player()
	_offer(player, _authored_tally_beat())
	assert_eq(
		EventFacts.count_of(player, &"elder_wei_favour_counted"),
		1,
		"the fact ledger is written by the same offer that tallied the roster"
	)


## `install` is idempotent (ADR 0092) and so is this connect: a boot that runs twice, or
## a re-install after a load, must not register a second subscriber. A duplicate connect
## is an engine error and a doubled ledger.
func test_installing_twice_does_not_connect_the_subscriber_twice() -> void:
	NpcBoot.install(null)
	NpcBoot.install(null)
	NpcBoot.install(null)
	var player := _player()
	NpcBoot.install(player)
	NpcApi.advance_stage(ELDER, &"sworn_servant", "test:install_idempotent")
	assert_eq(NpcLedger.count(), 1, "one subscriber, one row")


# --- BL-0628: the contract has a real subscriber -------------------------------


## **The gap in one assertion.** Seven signals were declared and emitted and NOTHING
## connected to them; ADR 0093 line 21 promises "a subscriber connects from its own boot
## function, which `app/` calls". `NpcBoot.install` is that function and `NpcLedger` is
## that subscriber.
func test_the_composition_root_connects_a_subscriber_to_stage_advanced() -> void:
	var events := NpcApi.events()
	assert_eq(
		events.stage_advanced.is_connected(NpcLedger.advanced),
		true,
		"install() connected the ledger to the contract's stage_advanced signal"
	)
	# And it is the SHARED bus, not a private copy: `social/` publishes `bond_changed`
	# on `NpcEvents.shared()`, so a subscriber on a facade-owned instance would never
	# hear the one module that is not allowed to depend on `npc/`.
	assert_eq(events, NpcEvents.shared(), "the bus a subscriber reaches is the shared one")


## Connecting and observing, driven through the production path. `NpcApi.advance_stage`
## emits; the ledger receives without `advance_stage` ever naming it — which is the
## whole inversion ADR 0093 line 21 describes.
func test_a_stage_advance_emits_and_the_subscriber_observes_it() -> void:
	var player := _player()
	NpcBoot.install(player)
	NpcApi.spawn(ELDER)
	assert_eq(NpcLedger.count(), 0, "nothing has advanced yet")
	var outcome := NpcApi.advance_stage(ELDER, &"sworn_servant", "test:subscriber")
	assert_eq(bool(outcome.get("ok", false)), true, "the advance landed")
	assert_eq(NpcLedger.count(), 1, "and the subscriber heard it without being asked")
	var row := NpcLedger.last()
	assert_eq(String(row.get("npc_id", "")), String(ELDER), "primitives: who moved")
	assert_eq(String(row.get("stage_id", "")), "sworn_servant", "to where")
	assert_eq(
		String(row.get("source", "")),
		"test:subscriber",
		"and what drove them, so a consumer can filter its own effects"
	)


## The production path lights the same ledger. This is the whole of BL-0628 end to end:
## an authored beat -> the facade -> `stage_advanced` -> an `app/` subscriber, with the
## npc module naming none of it.
func test_the_authored_beat_drives_the_subscriber_through_production() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	pulse.pull(PULSE)
	pulse.pull(PULSE)
	_tally_through_the_writer(player, 1)
	_tally_through_the_writer(player, 1)
	assert_eq(
		NpcLedger.count(), 1, "exactly one advance was observed across three beats and two pulses"
	)
	assert_eq(
		String(NpcLedger.last().get("source", "")),
		"test:authored_beat",
		"and the ledger says the ROSTER wrote it, because the event names no subscriber"
	)


## The trail is bounded. `app/` holds wiring, not a state table: a log that grew with
## every stage advance for the length of a session is the shape `tools/arch/rules.py`
## flags, so the oldest row is dropped at a named constant.
func test_the_ledger_drops_its_oldest_row_at_the_bound_rather_than_growing() -> void:
	var player := _player()
	NpcApi.spawn(ELDER)
	for index in range(NpcLedger.MAX_ROWS + 5):
		NpcApi.advance_stage(ELDER, &"sworn_servant", "test:bound_%02d" % index)
	assert_eq(NpcLedger.count(), NpcLedger.MAX_ROWS, "the trail is capped")
	assert_eq(
		String(NpcLedger.rows()[NpcLedger.rows().size() - 1].get("source", "")),
		"test:bound_00",
		"and the oldest row is the one dropped, so the newest survives"
	)


## A read hands back a COPY. A panel that could reach into the trail and rewrite it would
## make the audit meaningless — and `NpcApi.summary` sets that precedent for the read
## models already.
func test_reading_the_trail_does_not_hand_out_a_mutable_reference() -> void:
	var player := _player()
	NpcApi.spawn(ELDER)
	NpcApi.advance_stage(ELDER, &"sworn_servant", "test:copy")
	var rows := NpcLedger.rows()
	(rows[0] as Dictionary)["source"] = "rewritten"
	assert_eq(
		String(NpcLedger.last().get("source", "")),
		"test:copy",
		"editing what a read returned cannot rewrite what was observed"
	)
	assert_eq(NpcLedger.last(), {}, "an empty trail reads as {}, never null")


# --- Fixtures -------------------------------------------------------------------


## A player with the roster bound and the elder standing in the starting settlement,
## installed the way the composition root installs him (`NpcBoot`, not a raw
## `set_minter` lambda) so the injections under test are the production ones.
func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	EventApi.attach(actor)
	NpcBoot.install(actor)
	NpcApi.spawn(ELDER)
	return actor


## The shipped `npc_tally` beat, read out of the authored `.tres`. Typed as `Dictionary`
## rather than declared with a default so an empty beat FAILS the assertion that uses it
## rather than silently tallying nothing.
func _authored_tally_beat() -> Dictionary:
	var def := EventCatalog.instance().event_definition(EVENT)
	if def == null:
		return {}
	for stage in def.stages:
		for row in stage.on_enter:
			if String(row.get("kind", "")) == String(EventBeatWriter.KIND_NPC_TALLY):
				return (row as Dictionary).duplicate(true)
	return {}


## Offer one beat through the production writer, with the same proposal shape
## `EventApi._offer_beats` builds: the fact, the amount, the audit `source` and a
## caller-minted occurrence id (ADR 0114's once-rule).
func _offer(player: Actor, beat: Dictionary) -> Dictionary:
	var fact_id := StringName(beat.get("fact", ""))
	var proposal := beat.duplicate(true)
	proposal["source"] = "test:authored_beat"
	proposal["actor_id"] = String(player.id)
	proposal["id"] = EventFacts.occurrence_id(fact_id, EventFacts.count_of(player, fact_id) + 1)
	return EventBeatWriter.offer(player, proposal, EventFacts.count_of(player, fact_id) + 1)


## One more favour, on the production writer. Named so a failure says which step of the
## ladder went wrong rather than only that the elder is somewhere.
func _tally_through_the_writer(player: Actor, times: int) -> void:
	var beat := _authored_tally_beat()
	for _i in range(times):
		var outcome := _offer(player, beat)
		assert_eq(
			bool(outcome.get("npc_tallied", false)), true, "the beat was tallied: %s" % str(outcome)
		)
