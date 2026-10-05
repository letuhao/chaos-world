extends TestCase

## BL-0747: **a pull's single open is a BUDGET on openings, and every event the world
## allows is still reachable by pulling.**
##
## ## Why this file exists
##
## Two agents closed BL-0747 by "fixing" production code that was not broken, and left
## the real defect in place, because both believed the symptom was order-dependent.
## It is not: `tests/modules/npc/test_npc_tally_production_path.gd` fails **ALONE**,
## with all five of its pull-driven assertions red. Measured, not inferred — and this
## suite is where that fact is now pinned, because "it fails alone" is the single most
## expensive wrong assumption in the whole episode.
##
## ## The defect, in one sentence
##
## The fixture opened the elder's event DIRECTLY with `EventApi.begin`, which bypasses
## `EventApi.available` — the ordered, budgeted list a pull actually walks. So it
## proved the ladder worked while proving nothing about the pulse, and the moment a
## SECOND authored event shared `mortal_plains` and the ambient trigger, the first
## pull's one open went to `beast_tide_of_the_mortal_plains` and the fixture's
## "one pull opens my event" assumption became false. The content tree grew; the test
## read that as a broken chain.
##
## ## What is actually guaranteed, and is asserted here
##
## 1. **A refusal does not spend the budget.** Several events compete, one open is
##    allowed per pull, and the pulse keeps asking — so the events behind the winner
##    stay `available` instead of being skipped forever. This is the invariant
##    `WorldPulse._open_available` really owns, and the one the previous "fix" made
##    real.
## 2. **Reachability is not a timing accident.** However many events compete, a bounded
##    number of pulls gets them all open. That is what the corrected fixtures rely on,
##    and its absence is what makes a fixture flaky rather than wrong.
## 3. **The order is deterministic.** The catalog orders ids by STRING value, so which
##    event takes a pull's single open is a content fact and not a race — pinned so a
##    future reader does not go bisecting a deterministically-red suite.
##
## This suite belongs in `tests/app/`: the behaviour is the composition root's pull
## budget, and `tests/modules/npc/` is another agent's live surface.

const ELDER := &"elder_wei"
const EVENT := &"the_favour_of_elder_wei"
const LOCATION := "mortal_plains"
const PULSE := WorldPulse.PERIOD_SECONDS

## The ambient fact both contending events are triggered by, at period 1.
const TRIGGER_FACT := &"storm_front_sighted"

## Ids the hand-built probes register under. Deliberately NOT shipped ids: BL-0747
## closed the branch where `register` refused by erasing the shipped def for the id it
## claimed, so a probe under a shipped id is now safe — but it still could not be
## REMOVED, and a probe this suite owns has no business being confusable with content.
const REFUSED_ID := &"a_refused_probe_for_the_open_budget"
const OPENABLE_ID := &"b_openable_probe_for_the_open_budget"

## How many pulls [method test_every_event_the_world_allows_is_reachable_by_pulling]
## may spend. The competition is several events over a budget of one, so two is the
## floor; this is headroom. A `for` over a named constant, never a `while` on the
## ledger — `tests/arch_rules/test_no_unbounded_wait.gd` rules on that shape.
const PULL_BUDGET := 8


func setup() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	NpcCatalog.instance().reset()
	NpcCatalog.instance().load_authored()
	# The catalog is one process-wide cache and this suite reads SHIPPED content, so
	# the cache is dropped before the `.tres` under it is believed. `--suite test_npc`
	# runs this file in the same process as the npc suites, and a hand-built probe left
	# registered there must not describe the tree these assertions are about.
	EventCatalog.instance().reload()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcLedger.reset()
	EventCatalog.instance().reload()
	EventApi.attach(null)
	NpcApi.attach(null)


## **The regression, as one assertion.** With more than one event competing for a
## single open per pull, EVERY event the world allows is open after a bounded number
## of pulls. Reintroduce the defect by restoring `_open_available`'s old guard — break
## out on `out.size() >= MAX_OPENS_PER_PULL` BEFORE the `begin` call rather than after
## it — and this goes red with `the_favour_of_elder_wei` never reaching `active` and
## `elder_wei_petition_opened` never recorded: the pulse would open `beast_tide`, stop,
## and never ask again.
##
## The contention is measured on a SECOND actor whose trigger fact is satisfied without
## a pull, because on the actor under test the budget is spent inside the very first
## pull — sampling `available` afterwards would report one event and quietly turn the
## guard into an assertion about nothing.
func test_every_event_the_world_allows_is_reachable_by_pulling() -> void:
	# How many events a single pull would be asked about, measured before any budget is
	# spent. This is the contention the assertion below depends on.
	var contender := _player()
	WorldFact.record(contender, TRIGGER_FACT, 1)
	var competing := _available_ids(contender)
	assert_eq(
		competing.size() > 1,
		true,
		(
			(
				"the shipped tree offers more than one event at "
				+ LOCATION
				+ " behind the shared trigger, so this suite measures the CONTENDED budget"
			)
			+ " rather than a single-event world: "
			+ str(competing)
		)
	)

	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	# The ambient fact lands on the first pull, and that same pull spends its single
	# open on whichever contender sorts first.
	pulse.pull(PULSE)
	for _pull in range(PULL_BUDGET):
		if _available_ids(player).is_empty():
			break
		pulse.pull(PULSE)

	var open_ids := EventState.active_ids(EventApi.state(player))
	assert_eq(
		EventState.is_active(EventApi.state(player), EVENT),
		true,
		(
			(
				"the elder's event is reachable by pulling, within "
				+ str(PULL_BUDGET)
				+ " pulls after a competing event took the single open -- a REFUSAL must not"
			)
			+ " spend the budget, or the event behind the winner is never asked about again"
		)
	)
	assert_eq(
		EventFacts.count_of(player, &"elder_wei_petition_opened"),
		1,
		"and its opening beat fired, so the fact its stage authored is on the ledger"
	)
	# `MAX_OPENS_PER_PULL` is a budget, not a cap on the world: every contender ends up
	# open. That is what "reachable" means, and it is the half that fails under the
	# reintroduced defect.
	assert_eq(
		open_ids.size() >= 2,
		true,
		"every contending event ended up open within the bound: " + str(open_ids)
	)


## **The loser of a pull is still askable.** `begin` is the authority and is not what
## withheld it — `_open_available` simply stopped asking. Asserted on a fresh ledger so
## the two questions (is it reachable by pulling; is it refused by the director) can
## never be confused for one another, which is precisely the confusion that cost two
## agents their diagnosis.
func test_an_event_a_pull_did_not_open_is_still_available_rather_than_refused() -> void:
	var player := _player()
	var pulse := WorldPulse.new(player, BeatDirector.new())
	pulse.pull(PULSE)
	var waiting := _available_ids(player)
	assert_eq(
		waiting.has(EVENT),
		true,
		"the event the pull did not open is still `available`, not consumed or refused"
	)
	var ledger := EventApi.state(player)
	var direct := EventApi.begin(player, EVENT, 1)
	assert_eq(
		bool(direct.get("ok", false)),
		true,
		(
			"and `begin` on that same ledger accepts it right now, so the pull withheld"
			+ " nothing: "
			+ str(direct)
		)
	)
	assert_eq(
		EventState.is_active(ledger, EVENT) == false,
		true,
		"while the ledger taken BEFORE that call had it closed"
	)


## **The invariant `_open_available` actually owns: a REFUSAL does not spend the
## budget.** This is the only assertion here that separates the two budgets, and the
## shipped content alone cannot demonstrate it — which is why it needs a hand-built def.
##
## Two hand-built events are registered on top of the shipped tree, both at
## `mortal_plains`, both behind a trigger this actor already satisfies, and
## `MAX_OPENS_PER_PULL` is 1:
##
##   - `a_refused_...` — well-formed enough for the catalog to admit it, so it IS a
##     candidate, but authors no stage, so `begin` refuses it with a NAMED reason.
##   - `b_openable_...` — the same, plus one stage, so `begin` opens it.
##
## Both sort ahead of the shipped `beast_tide_of_the_mortal_plains`, so the pair sits at
## the very front of `available` and the pull meets them first. A refusal must not cost
## the budget, so the pull's one open goes to `b_openable_`.
##
## Mutate `_open_available` to charge the budget to candidates ASKED — break out once any
## `begin` call has been made, regardless of its answer — and this goes RED: `b_openable_`
## is never asked about, `opened` is 0, and the failure reads "a refusal spent the pull's
## only open". The suite's other two budget assertions stay GREEN under that mutation,
## because with the shipped tree the first candidate always opens and the two budgets
## coincide — which is exactly why they are not sufficient on their own.
##
## Both defs are registered under ids the tree does not ship and are dropped by
## `reload()` in `setup()` and `teardown`, so they cannot reach any other suite.
func test_a_refused_candidate_does_not_spend_the_pulls_single_open() -> void:
	var refused := _probe_def(REFUSED_ID)
	var openable := _probe_def(OPENABLE_ID)
	EventCatalog.instance().register(refused)
	EventCatalog.instance().register(openable)

	var player := _player()
	WorldFact.record(player, TRIGGER_FACT, 1)
	var candidates := _available_ids(player)
	assert_eq(
		candidates.size() >= 2 and candidates[0] == REFUSED_ID,
		true,
		(
			"the refused probe sorts FIRST in `available`, with the openable one right"
			+ " behind it: "
			+ str(candidates)
		)
	)

	var pulse := WorldPulse.new(player, BeatDirector.new())
	var report := pulse.pull(PULSE)
	assert_eq(
		EventState.has_resolved(EventApi.state(player), REFUSED_ID),
		false,
		"the refusable def is not resolved either: `begin` simply declined to open it"
	)
	assert_eq(
		int(report["opened"]),
		1,
		"the pull still opened its one event despite the refusal ahead of it"
	)
	assert_eq(
		EventState.is_active(EventApi.state(player), OPENABLE_ID),
		true,
		(
			"and the event BEHIND the refused candidate is the one that opened -- a"
			+ " refusal must not spend the pull's single open"
		)
	)


## **The order that decides the single open is the STRING order, not load order.**
## Asserted rather than assumed: a reader who believes the order is unspecified will
## read the symptom as nondeterminism and go bisecting a suite that is deterministically
## red. This is the second half of BL-0747, and it is the half that makes the symptom
## reproducible enough to diagnose at all.
func test_the_order_deciding_the_single_open_is_the_string_order() -> void:
	var ids := EventCatalog.instance().event_ids()
	var as_strings: Array[String] = []
	for event_id in ids:
		as_strings.append(String(event_id))
	var by_string := as_strings.duplicate()
	by_string.sort()
	assert_eq(
		as_strings,
		by_string,
		"the catalog's order decides which event takes a pull's single open: " + str(as_strings)
	)
	var at_here := EventCatalog.instance().at_location(StringName(LOCATION))
	assert_eq(
		at_here.size() > 1,
		true,
		"mortal_plains really does ship several events, which is the contention itself"
	)


# --- Fixtures -------------------------------------------------------------------


## A player standing in the elder's settlement with the roster installed, built the way
## the composition root builds one. `EventApi.set_location` is load-bearing: the
## events here carry `location_id = mortal_plains`, and `available` filters a located
## event out before its trigger is read.
func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	EventApi.attach(actor)
	EventApi.set_location(actor, StringName(LOCATION))
	NpcBoot.install(actor)
	NpcApi.spawn(ELDER)
	return actor


func _available_ids(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for row in EventApi.available(player):
		out.append(StringName((row as Dictionary).get("event_id", "")))
	return out


## A WELL-FORMED def — `EventCatalog.register` refuses anything with `problems()`, so
## an unusable probe would never become a candidate and the test would prove nothing.
## The ONLY difference between the refused and the openable probe is whether `stages` is
## empty, which is what `EventApi.begin` refuses on. Both sort ahead of the shipped
## `beast_tide_of_the_mortal_plains` and sit at the same location behind the same
## trigger, which is what puts a refusal directly in front of the pull's single open.
func _probe_def(id: StringName) -> EventDef:
	var def := EventDef.new()
	def.id = id
	def.display_name = "A Probe For The Open Budget"
	def.kind = EventDef.KIND_DISASTER
	def.trigger = {"verb": &"fact", "id": TRIGGER_FACT, "need": 1}
	def.location_id = StringName(LOCATION)
	if id == OPENABLE_ID:
		var stage := EventStageDef.new()
		stage.stage_id = &"only"
		stage.display_name = "Only"
		def.stages.append(stage)
	return def
