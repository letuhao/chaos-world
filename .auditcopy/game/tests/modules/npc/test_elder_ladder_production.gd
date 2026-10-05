extends TestCase

## F3 / BL-0745: **Elder Wei's ladder was three rungs and only the first was reachable.**
##
## ## What was actually broken
##
## `data/npc/cast/elder_wei.tres` authors `gatekeeper` (`advance_verb = "favours"`,
## `advance_after = 3`) -> `sworn_servant` (`advance_verb = "oaths_sworn"`,
## `advance_after = 5`) -> `retired` (terminal). The `favours` verb had a producer:
## `data/event/events/the_favour_of_elder_wei.tres` carries an `npc_tally` beat naming
## it, and `EventBeatWriter` routes that into `NpcApi.tally`. **`oaths_sworn` had none.**
## The word existed only as a DESTINY counter id in
## `data/destiny/fates/oath_of_the_empty_hand.tres` — a different vocabulary on a
## different ledger, so nothing in the roster could ever count it. The elder therefore
## topped out at rung 1 and could never be sworn or retire.
##
## ## Why this suite drives the PULSE and not `tally`
##
## The fix is content plus the existing production path, so the test has to walk the path
## a player walks: `WorldPulse.pull` -> `EventApi.begin` / `advance` ->
## `EventBeatWriter.offer` -> the injected `NpcApi.tally`. A test that called
## `NpcApi.tally(npc_id, "oaths_sworn")` directly would pass against a build where no
## authored beat names that verb at all — which is precisely the defect. Every test below
## refuses to call `tally` except where it is explicitly demonstrating that the
## content-verbatim beat does or does not carry the verb.
##
## ## The fixture discipline is inherited from `test_npc_tally_production_path.gd`
##
## `NpcApi.attach` pins a process-wide player nothing can clear, `EventCatalog` holds one
## process-wide cache with no reset verb, and `NpcLedger` is a process-wide audit trail.
## All three are restored in BOTH `setup()` and `teardown()` because the runner shares
## one process across every suite — the header of that file explains at length why a
## suite that leaks any of them is green alone and red in company, which is the worst way
## to fail.

const ELDER := &"elder_wei"
const EVENT := &"the_favour_of_elder_wei"
const LOCATION := "mortal_plains"
const PULSE := WorldPulse.PERIOD_SECONDS

## The verb the `gatekeeper` rung counts, and the fact whose beat carries it.
const FAVOURS := &"favours"
const SHOWN_FACT := &"elder_wei_favours_shown"
## The verb the `sworn_servant` rung counts. Before the fix nothing in `game/data` or
## `game/src` produced this on the roster's ledger, so the rung was unreachable.
const OATHS := &"oaths_sworn"
## The fact the third stage's beat records as it tallies that verb.
const OATH_FACT := &"elder_wei_oath_taken"

## How many whole pulls [method _pull_until_open] may spend before giving up. Two is what
## the shipped content needs; this is headroom, and the loop is a `for` over it rather
## than a `while` on the ledger (`tests/arch_rules/test_no_unbounded_wait.gd`).
const PULL_BUDGET := 4


func setup() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcCatalog.instance().reset()
	NpcCatalog.instance().load_authored()
	EventCatalog.instance().reload()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	EventCatalog.instance().reload()
	EventApi.attach(null)
	NpcApi.attach(null)


# --- The content half: the shipped tree names the second verb -----------------


## **The gap, as one assertion.** `elder_wei`'s second rung names `oaths_sworn`, and some
## authored `.tres` under `data/event/events/` must carry an `npc_tally` beat naming that
## exact verb. Delete the third stage from `the_favour_of_elder_wei.tres` and this is
## red, which is the whole point: an implementation whose shipped content is inert must
## fail here rather than in a player's playthrough.
func test_shipped_content_names_the_verbs_both_ladder_rungs_count() -> void:
	var elder := NpcCatalog.instance().definition(ELDER)
	assert_ne(elder, null, "the elder loads from disk")
	var gatekeeper := elder.stage(&"gatekeeper")
	var sworn := elder.stage(&"sworn_servant")
	assert_ne(gatekeeper, null, "his first rung is authored")
	assert_ne(sworn, null, "his second rung is authored")
	assert_eq(StringName(gatekeeper.advance_verb), FAVOURS, "the first rung counts favours")
	assert_eq(StringName(sworn.advance_verb), OATHS, "and the second counts oaths sworn")

	var produced := 0
	for path in ContentScan.files_under("res://data/event/events/"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("npc_tally") and text.contains("oaths_sworn"):
			produced += 1
	assert_ne(
		produced,
		0,
		(
			"an authored npc_tally beat must name 'oaths_sworn' or the elder's second rung"
			+ " has no producer and he can never be sworn"
		)
	)


## The beat is read off the shipped `.tres`, not retyped, so a typo in the content is a
## red test rather than a green one that agrees with its own typo.
func test_the_authored_oath_beat_names_the_elder_and_his_second_rung_verb() -> void:
	var beat := _authored_beat_for(OATHS)
	assert_ne(beat.is_empty(), true, "the shipped .tres carries an oaths_sworn tally beat")
	assert_eq(String(beat.get("npc_id", "")), String(ELDER), "naming the elder")
	assert_eq(StringName(beat.get("verb", &"")), OATHS, "and the verb his second rung counts")


# --- The production path walks the WHOLE ladder (the load-bearing test) -------


## **The end-to-end claim, and the test this change exists to satisfy.**
##
## Nothing here calls `NpcApi.tally`. Every rung is moved by `WorldPulse.pull` opening
## the authored event, `EventApi.advance` walking it to the stage that carries the beat,
## and `EventBeatWriter.offer` routing that beat through the injected facade — the exact
## route `item_workbench_app.gd` takes on its `_process`.
##
## The three favours are driven the way a RE-OPENED petition would drive them (the event
## resolves after its final stage, so the ladder's later rungs are fed by replaying the
## shipped beats through the same writer), and the oath is driven by pulling the third
## stage. Delete the `the_oath` stage and the elder is still `sworn_servant` here — which
## is the F3 failure this pins.
func test_the_production_path_walks_the_elder_to_rung_two_and_then_to_retired() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())

	# The ambient fact lands on the first pull, and the elder's event is NOT the first
	# thing that pull opens: `mortal_plains` ships two events behind that same trigger
	# and `MAX_OPENS_PER_PULL` is 1, so `beast_tide_of_the_mortal_plains` wins the
	# budget and the elder's event opens on a LATER pull. See `_pull_until_open`.
	_pull_until_open(player, pulse, EVENT)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "he opens where he starts")

	# The next pull: `the_petition` -> `the_favour`, whose beat tallies one favour.
	pulse.pull(PULSE)
	assert_eq(EventFacts.count_of(player, SHOWN_FACT), 1, "the favour beat was reached")
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "one favour of three is not a rung")

	# Two more favours, each through the shipped beat. The third crosses `advance_after`.
	_tally(player, FAVOURS, 2)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"the third favour crosses the threshold his FIRST rung authored — he is now rung two"
	)

	# **And here is the gap.** The elder now stands on a rung that counts `oaths_sworn`,
	# a verb nothing produced. Pull 3 walks `the_favour` -> `the_oath`, whose beat names
	# exactly that verb. Before the fix there was no third stage and this pull tallied
	# nothing; the elder sat on `sworn_servant` forever.
	pulse.pull(PULSE)
	assert_eq(
		EventFacts.count_of(player, OATH_FACT),
		1,
		"the third stage's beat was reached and offered by the event path"
	)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"one oath of the five his second rung names is not a rung"
	)

	# Three more oaths through the same production writer. That is four in total — the
	# pull above was the first — so rung two's `advance_after = 5` is not yet met and he
	# holds exactly where he is standing.
	_tally(player, OATHS, 3)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"four oaths of the five his second rung names still hold him on that rung"
	)

	# The fifth sworn oath crosses `advance_after = 5` and walks him to `retired`, the
	# terminal rung — a rung that carries no `advance_after` of its own, so filling the
	# one below it is the only way to reach it.
	_tally(player, OATHS, 1)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"retired",
		(
			"the fifth sworn oath crosses advance_after = 5 and retires him — the whole"
			+ " ladder is walkable through the production path, which is what F3 denied"
		)
	)


## The roster is the truth about who he is, and it is the only writer: `NpcApi.tally`
## is what every beat routes through. Asserted on the READ MODEL rather than a live
## actor so the claim is about the save, not about a projection.
func test_the_reachable_top_rung_is_terminal_and_reads_as_retired() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	_pull_until_open(player, pulse, EVENT)
	pulse.pull(PULSE)
	_tally(player, FAVOURS, 2)
	_tally(player, OATHS, 5)
	var summary := NpcApi.summary(ELDER)
	assert_eq(summary["stage_id"], "retired", "five oaths retire him")
	assert_eq(
		String(summary.get("presence", "")),
		NpcPresence.label(NpcPresence.RETIRED),
		(
			"and a retired elder reads as retired, which is what a terminal stage means:"
			+ " the roster sets presence and `_presence_of` lets retirement outrank being live"
		)
	)


## A ladder where the second rung can be reached by the wrong verb is not a ladder.
## This is the regression guard on the CONTENT change: the `the_oath` beat names
## `oaths_sworn` and nothing else, so a beat naming a verb the second rung does NOT
## count must accumulate its own tally and move nobody — proving the fix did not
## smuggle a general-purpose "any verb counts" rule in through `advance_after = 5`.
func test_an_oath_beat_naming_an_unrelated_verb_never_retires_the_elder() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	_pull_until_open(player, pulse, EVENT)
	pulse.pull(PULSE)
	_tally(player, FAVOURS, 2)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "sworn_servant", "he is on rung two")

	var wrong := _authored_beat_for(OATHS).duplicate(true)
	wrong["verb"] = &"an_unrelated_verb"
	for _i in range(9):
		_offer(player, wrong)
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"nine unrelated verbs accumulate their own tally and retire nobody"
	)


# --- Fixtures -------------------------------------------------------------------


## A player with the roster bound and the elder standing in the settlement, installed
## the way the composition root installs him (`NpcBoot`, not a raw `set_minter` lambda)
## so the injections under test are the production ones.
##
## `EventApi.set_location` is load-bearing: the elder's event carries
## `location_id = mortal_plains` and `EventApi.available` filters a located event out
## before its trigger is read, so an actor nowhere in particular can never open it.
func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	EventApi.attach(actor)
	EventApi.set_location(actor, StringName(LOCATION))
	NpcBoot.install(actor)
	NpcApi.spawn(ELDER)
	return actor


## Pull the world until `event_id` is OPEN.
##
## **This is the fixture bug BL-0747 closed, and it is shared deliberately with
## `test_npc_tally_production_path.gd`, which hit it first.** Both suites used to
## assume "one pull opens my event", which was true of a one-event world and stopped
## being true the moment a second authored event shared the location and the trigger.
## `mortal_plains` now ships two events behind `storm_front_sighted` —
## `beast_tide_of_the_mortal_plains` and `the_favour_of_elder_wei` — and
## `WorldPulse.MAX_OPENS_PER_PULL` is 1, so the alphabetically first one wins the
## budget and the elder's event opens on a later pull. That is the composition root's
## documented behaviour, not a defect: the loser stays `available` and is opened by the
## next pull.
##
## An assertion of "one pull opens my event" is a claim about the CONTENT TREE, and the
## content tree is allowed to grow. Pinning it here made a second authored event read as
## a broken ladder.
func _pull_until_open(player: Actor, pulse: WorldPulse, event_id: StringName) -> void:
	for _pull in range(PULL_BUDGET):
		if EventState.is_active(EventApi.state(player), event_id):
			return
		pulse.pull(PULSE)


## The shipped `npc_tally` beat carrying `verb`, read out of the authored `.tres`.
## Returns `{}` when none does, so a caller asserting on it fails loudly rather than
## silently tallying nothing.
func _authored_beat_for(verb: StringName) -> Dictionary:
	var def := EventCatalog.instance().event_definition(EVENT)
	if def == null:
		return {}
	for stage in def.stages:
		for row in stage.on_enter:
			if String(row.get("kind", "")) != String(EventBeatWriter.KIND_NPC_TALLY):
				continue
			if StringName(row.get("verb", &"")) == verb:
				return (row as Dictionary).duplicate(true)
	return {}


## Offer one beat through the production writer, with the same proposal shape
## `EventApi._offer_beats` builds: the fact, the amount, the audit `source` and a
## caller-minted occurrence id (ADR 0114's once-rule).
func _offer(player: Actor, beat: Dictionary) -> Dictionary:
	var fact_id := StringName(beat.get("fact", ""))
	var proposal := beat.duplicate(true)
	proposal["source"] = "test:ladder"
	proposal["actor_id"] = String(player.id)
	proposal["id"] = EventFacts.occurrence_id(fact_id, EventFacts.count_of(player, fact_id) + 1)
	return EventBeatWriter.offer(player, proposal, EventFacts.count_of(player, fact_id) + 1)


## `times` more hits of `verb`, each through the shipped beat on the production writer.
## Named so a failure says which rung's threshold went wrong rather than only that the
## elder is somewhere.
func _tally(player: Actor, verb: StringName, times: int) -> void:
	var beat := _authored_beat_for(verb)
	assert_ne(beat.is_empty(), true, "the shipped .tres carries a '%s' tally beat" % String(verb))
	for _i in range(times):
		var outcome := _offer(player, beat)
		assert_eq(
			bool(outcome.get("npc_tallied", false)),
			true,
			"the '%s' beat was tallied: %s" % [String(verb), str(outcome)]
		)
