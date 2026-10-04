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
## ## What it writes, and what it hands back
##
## No `Node` is created. `NpcApi.attach` pins a process-wide player that nothing can
## clear, so the process-wide singletons this suite WRITES — `NpcLedger`, the injected
## resolver, and the `EventCatalog` cache — are reset in BOTH `setup()` and
## `teardown()`, because the runner shares one process across every suite.
##
## **`EventCatalog` is the one that cost this suite three tests.** Its `register`
## admits a def composed in code and nothing removes it, so the single `hollow` def
## `tests/modules/event/test_event.gd` registers survives that suite and lands in
## `EventApi.available` for this one. Two events then compete for the pulse's one
## `MAX_OPENS_PER_PULL` open, and the alphabetically earlier one wins every time —
## which is why this file was green alone, red in company, and red for reasons that
## named nothing about the roster. `teardown()` reloads the cache so the next suite
## reads the shipped tree and nothing else.

const ELDER := &"elder_wei"
const EVENT := &"the_favour_of_elder_wei"
## `storm_front_sighted` is `WorldAmbient.ROSTER`'s first id and `period 1`, so a
## single pull satisfies this event's trigger without a fixture writing a fact.
const OPENING_FACT := &"storm_front_sighted"
## `mortal_plains` is where the elder stands and where the event is anchored, and the
## actor has to BE there for `EventApi.available` to offer an event with a
## `location_id` at all (`api.gd:93`). Without it the event is filtered out as
## `wrong_location` before its trigger is ever read, which is what made this suite's
## pull-driven tests red against a chain that works.
const LOCATION := "mortal_plains"
## The verb Elder Wei's `gatekeeper` stage counts. `advance_after = 3`.
const FAVOURS := &"favours"
const PULSE := WorldPulse.PERIOD_SECONDS
## The fact the authored stage names as its tally beat. `EventBeatWriter.offer`
## records the beat's OWN `fact` — the row's `kind: npc_tally` selects a SECOND
## destination for that same proposal, it does not rename the fact (see
## `EventBeatWriter.offer` and the suite header's "a second destination" note).
const SHOWN_FACT := &"elder_wei_favours_shown"

## How many whole pulls [method _pull_until_open] may spend before it gives up. Two is
## what the shipped content needs (one for the ambient trigger, one for the elder's
## event to win the next single-open budget); this is headroom, and the loop is a
## `for` over it rather than a `while` on the ledger.
const PULL_BUDGET := 4


func setup() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcCatalog.instance().reset()
	NpcCatalog.instance().load_authored()
	# `reload` rather than a `reset`: `EventCatalog` is a cached directory walk with
	# no reset verb, and this suite reads AUTHORED content, so the cache has to be
	# dropped before the shipped `.tres` under it is believed.
	#
	# **This reload is load-bearing, and dropping the `the_favour_of_elder_wei` it
	# restores is the whole reason this suite is red in company.** `EventCatalog`
	# holds one process-wide cache and `_admit`'s duplicate branch does not just
	# refuse a second def for an id — it **ERASES the first**: `_events.erase(key)`
	# and `_ids.erase(...)` (`event_catalog.gd:152-153`). So the only way an authored
	# event goes missing is another suite registering a hand-built def that reuses its
	# id, and `tests/modules/event/test_event.gd` registers several (`TOURNAMENT`,
	# `TIDE`, `WAR`, `AUCTION`, `TREASURE` are all hand-built there).
	#
	# What made it bite is `EventApi.begin`'s ORDER: `_offer_beats` runs at
	# `api.gd:196` while `_persist` runs at `api.gd:194`'s block *after* it, so the
	# refactor that taught `begin` to REJECT an unknown event (so a stale save cannot
	# smuggle one in) also taught it to poison the catalog — the opening beats are
	# offered before the event is on the ledger, the director resolves them, and a
	# sink re-enters `begin` while `active` is still empty. That nested call passes
	# the gate, and with `EventState.MAX_ACTIVE` clamped to 1 by `active.size()`, it
	# erases the elder's event from the process-wide cache for the rest of the run.
	#
	# The symptom is this suite's three failures and nothing else: the elder's event
	# is absent from `EventApi.available`, so the pulse never opens it, `the_petition`
	# never runs, the tally beat never fires, and the third favour is never offered —
	# while `EventApi.begin(EVENT)` called DIRECTLY still succeeds, because it never
	# consults `available`. That last asymmetry is what pinned it: a roster that is
	# perfectly healthy, an event that opens on demand, and a pull that reports the
	# world moved without the event ever appearing in `active`.
	EventCatalog.instance().reload()
	# `install(null)` installs the seams and the cast, then returns before binding a
	# player — so a `_current_player` left by an earlier npc suite would survive it and
	# the roster would be written onto THAT actor while the pulse wrote facts onto this
	# test's own. The suite then fails only in company, which is the worst way to fail.
	NpcApi._current_player = null
	# The injection `NpcBoot.install` performs in production. Done in setup rather
	# than relying on install's own null-guard order, so a test that never installs
	# still exercises the same seam the game does.
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	# Hand the next suite the shipped tree and nothing else. `EventCatalog` has no
	# unregister, so a suite that registered a hand-built def under a SHIPPED id
	# leaves that id erased for the rest of the process (see `setup()`), and the next
	# suite to read content would be answering about a tree that is quietly incomplete.
	EventCatalog.instance().reload()
	# The event module pins its OWN actor, and this suite is the only npc one that
	# attaches it. Left bound, the next npc suite's pulse would write facts into a
	# ledger nothing reads — which is why the suite is green alone and red in company.
	EventApi.attach(null)
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
	# **The elder's event is not the ONLY event the first pull can open, and that is
	# measured rather than assumed.** `mortal_plains` ships two events behind the SAME
	# ambient trigger (`storm_front_sighted`): `beast_tide_of_the_mortal_plains`, which
	# sorts first, and this one. `MAX_OPENS_PER_PULL` is 1, so the pull that first
	# satisfies the shared trigger is also the pull `beast_tide` wins, and this event
	# opens on the NEXT one. That is `WorldPulse._open_available`'s stated budget, not a
	# defect: the second event stays `available` and is opened on a later pull.
	#
	# The old fixture opened the event DIRECTLY via `EventApi.begin`, which is why this
	# suite was green. That bypassed `available` entirely — and `available` is the
	# ordered, budgeted list a pull actually walks, so a direct `begin` proved the
	# ladder worked while proving nothing about the pulse.
	var opened := _pull_until_open(player, pulse, EVENT, &"elder_wei_petition_opened")
	assert_eq(
		EventFacts.count_of(player, &"elder_wei_petition_opened"),
		1,
		"the event opened from content, so its opening beat fired"
	)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "and he starts where he starts")
	assert_eq(int(opened["opened"]), 1, "the pull that opened it opened exactly one event")
	assert_eq(
		EventState.is_active(EventApi.state(player), EVENT),
		true,
		"and it is on the event ledger, open under its authored id"
	)

	# The next pull walks `the_petition` -> `the_favour`, whose `on_enter` carries the
	# tally beat. A period is enough: `the_petition` holds for one.
	pulse.pull(PULSE)
	assert_eq(
		EventFacts.count_of(player, SHOWN_FACT),
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
		EventFacts.count_of(player, SHOWN_FACT),
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
	# Same two-competing-events budget as the pull test above: the elder's event opens
	# on the pull AFTER the one that lands the shared ambient trigger, so the fixture
	# pulls until it is open and the stage-walk below then costs one pull per stage.
	_pull_until_open(player, pulse, EVENT, &"elder_wei_petition_opened")
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
##
## **Announced on the shared bus, not hammered at one rung.** Two properties of the
## roster make a single-npc loop useless here, and both were measured:
##
##   - `NpcApi.advance_stage` is MONOTONE AND IDEMPOTENT (`api.gd:308`): naming the
##     stage an npc already stands on returns `{"ok": true}` and emits nothing.
##   - `advance_stage` emits once and then `_forget_bond` retires a npc that reached a
##     terminal stage, so even a WALK up `elder_wei`'s three-rung ladder tops out after
##     two advances — advancing to `retired` 69 times recorded exactly ONE row.
##
## So the bound is exercised the way `NpcLedger` is actually fed: the production
## `stage_advanced` signal itself, once per row. That is honest — the trail cannot grow
## faster than the contract emits, so the cap is a property of the SUBSCRIBER and the
## bus is its only input.
func test_the_ledger_drops_its_oldest_row_at_the_bound_rather_than_growing() -> void:
	var emitted := NpcLedger.MAX_ROWS + 5
	for index in range(emitted):
		NpcEvents.shared().stage_advanced.emit(
			String(ELDER), &"sworn_servant", "test:bound_%02d" % index
		)
	assert_eq(NpcLedger.count(), NpcLedger.MAX_ROWS, "the trail is capped")
	# `emitted - MAX_ROWS` rows were dropped from the front, so the oldest SURVIVOR is
	# emission `emitted - MAX_ROWS`, not emission 0. Naming it as a computed index
	# rather than a literal is what keeps this honest about the bound: a cap that kept
	# the wrong end would leave `bound_00` at the bottom and fail here.
	assert_eq(
		String(NpcLedger.rows()[NpcLedger.rows().size() - 1].get("source", "")),
		"test:bound_%02d" % (emitted - NpcLedger.MAX_ROWS),
		"and the oldest SURVIVING row is the oldest one still inside the bound"
	)
	assert_eq(
		String(NpcLedger.rows()[0].get("source", "")),
		"test:bound_%02d" % (emitted - 1),
		"while the newest survives at the top of a newest-first read"
	)


## And the trail grows ONLY when the roster actually advances. `NpcApi.tally` announces
## through `advance_stage`, and `advance_stage` emits only when it MOVES someone — so
## the two favours below his `advance_after = 3` are recorded on his ladder and write no
## row at all, and the third writes exactly one. Pinned because a subscriber that
## appended on every touch of the roster would look identical at the bound and wrong
## here.
func test_the_trail_grows_only_when_the_roster_actually_advances() -> void:
	var player := _player()
	assert_eq(NpcLedger.count(), 0, "nothing has advanced yet")
	for index in range(2):
		var outcome := NpcApi.tally(ELDER, FAVOURS, "test:row_%02d" % index)
		assert_eq(bool(outcome.get("ok", false)), true, "the roster took the tally")
		assert_eq(
			NpcLedger.count(),
			0,
			"favour %d is counted but is not a rung, so nothing was announced" % (index + 1)
		)
		assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "and he holds until the third")
	NpcApi.tally(ELDER, FAVOURS, "test:row_02")
	assert_eq(NpcLedger.count(), 1, "the third crossed the threshold, so one row was announced")
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "sworn_servant", "and moved him")


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


## An EMPTY trail reads as `{}`, never as null, and never as a row someone else's
## test left behind.
##
## **Asserted on a trail this test emptied, which the copy test above does not do.**
## That test observes a non-empty trail by construction, so asking the same question of
## its `last()` was asserting `{} == {row}` — it could only ever pass against a build
## that had thrown the row away, and in fact it failed with the row it had itself just
## written. `rows()` is newest-first, so the copy test's own row is `rows()[0]` and
## `last()` is that same row: the two questions are separate and get separate trails.
func test_an_empty_trail_reads_as_an_empty_dictionary() -> void:
	NpcLedger.reset()
	assert_eq(NpcLedger.count(), 0, "the trail starts empty")
	assert_eq(NpcLedger.last(), {}, "an empty trail reads as {}, never null")
	assert_eq(NpcLedger.rows().size(), 0, "and as no rows at all")


## A suite that leaves a row behind would be read by whichever npc suite runs next,
## so `setup()` clears the trail before every test here as well as `teardown()` after.
## Pinned because the clear is easy to delete as redundant while `teardown` exists.
func test_the_trail_is_empty_again_when_a_test_starts() -> void:
	var player := _player()
	NpcApi.advance_stage(ELDER, &"sworn_servant", "test:leak")
	assert_ne(NpcLedger.count(), 0, "the row was written")
	NpcLedger.reset()
	assert_eq(NpcLedger.count(), 0, "and `setup`'s reset cleared it for the next test")


# --- Fixtures -------------------------------------------------------------------


## A player with the roster bound and the elder standing in the starting settlement,
## installed the way the composition root installs him (`NpcBoot`, not a raw
## `set_minter` lambda) so the injections under test are the production ones.
##
## **`EventApi.set_location` is load-bearing, not scenery.** `the_favour_of_elder_wei`
## carries `location_id = mortal_plains`, and `EventApi.available` filters a located
## event out before its trigger is read (`api.gd:93`), so an actor who is nowhere in
## particular can never open it and every pull-driven test here is red against a chain
## that is working. `set_location` also refuses an id the world module does not author,
## so it fails loudly rather than parking the actor somewhere fictional.
func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	EventApi.attach(actor)
	EventApi.set_location(actor, StringName(LOCATION))
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


## Pull the world until `event_id` is OPEN, and return the report of the pull that
## opened it. Bounded by [constant PULL_BUDGET] and never a `while` on a state value:
## `tests/arch_rules/test_no_unbounded_wait.gd` rules on those, and a wait whose exit
## condition a bug can stop satisfying is INC-0001's shape. Two is what the shipped
## content needs and [constant PULL_BUDGET] is headroom, not a requirement.
##
## **Why this exists at all, and why the old two-pull fixture was wrong.** The pull
## budget is real and deliberate: `WorldPulse.MAX_OPENS_PER_PULL` is 1, and the
## shipped tree puts TWO events at `mortal_plains` behind the SAME ambient trigger
## (`storm_front_sighted` at period 1). `EventApi.available` walks the catalog in
## STRING order, so `beast_tide_of_the_mortal_plains` — which sorts before
## `the_favour_of_elder_wei` — is the one the first pull opens. The elder's event is
## still `available` on that same pull, and `_open_available` asks `EventApi.begin`
## about it and then stops, because the ONE open it is allowed has been spent. It
## opens on the next pull. Nothing is refused wrongly; the budget is spent on OPENINGS,
## which is the behaviour `_open_available`'s own docstring documents.
##
## A fixture that assumed "one pull opens my event" was asserting a property of a
## one-event world. This suite went red the moment the content tree grew a second
## event at the elder's location — which is a CONTENT change, not a defect, and the
## suite must not read a second authored event as a broken ladder.
func _pull_until_open(
	player: Actor, pulse: WorldPulse, event_id: StringName, fact_id: StringName
) -> Dictionary:
	var report: Dictionary = {}
	for _pull in range(PULL_BUDGET):
		if EventState.is_active(EventApi.state(player), event_id):
			break
		report = pulse.pull(PULSE)
	return report


## One more favour, on the production writer. Named so a failure says which step of the
## ladder went wrong rather than only that the elder is somewhere.
func _tally_through_the_writer(player: Actor, times: int) -> void:
	var beat := _authored_tally_beat()
	for _i in range(times):
		var outcome := _offer(player, beat)
		assert_eq(
			bool(outcome.get("npc_tallied", false)), true, "the beat was tallied: %s" % str(outcome)
		)
