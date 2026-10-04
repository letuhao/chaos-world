extends TestCase

## The WHOLE chain, driven from the real boot path: a world period elapses, the
## composition root mints a beat, the director records it, a registered sink claims
## it, and an authored quest completes.
##
## ## Why this file exists
##
## ADR 0117 measured the shape of the defect precisely: `EventApi` had zero
## production callers, `BeatDirector` had **zero production instances**, and
## `QuestBeatHandler` / `EventBeatSink` were named by nothing outside a test. Every
## one of those suites was green. `test_beat_director.gd` builds its own
## `BeatDirector` and its own `WorldBeat`, so it measured the director and nothing
## about whether a player could reach one — a suite that stays green while the chain
## is dead, which is the mistake this file exists to make impossible.
##
## So nothing below constructs a `BeatDirector`, hands a `WorldBeat` to one, or
## records a fact by hand. Every assertion reads state that only exists because
## [code]ItemWorkbenchApp._ready[/code] wired it and the app's own `advance_world`
## advanced it.
##
## ## What "the chain is live" means here, precisely
##
##   `advance_world(periods)` -> `WorldPulse.advance_periods(periods)`
##     -> a whole period elapses
##     -> `EventApi.advance(actor, periods)`  (the world's own ladder)
##     -> a beat minted by the OWNER OF THE MOMENT
##        -> `BeatDirector.offer` -> `WorldFact.record`
##        -> `QuestBeatHandler.handles` -> `QuestApi.advance` -> quest completed
##
## Removing any link turns one of the assertions below red, and each mutation was
## run and observed.
##
## ## `_process` is NOT in that chain any more
##
## It used to be the first link, through `WorldPulse.pull(delta)`. **There is no
## real-time clock for the world (ADR 0167, ADR 0173)**: idle is frozen and the world
## moves only when the player acts. `_process` keeps the TURN TIER and the death poll
## and nothing else, so the two tests below that still drive it are pinning the
## ABSENCE of movement — "a frame moves the world by nothing" — rather than a
## conversion. `advance_world` is the only way time moves in this suite.

## The period the composition root accrues. Read from the pulse rather than typed
## here, so a retune of the cadence cannot make this suite lie about which fact it
## is watching.
const PERIOD_FACT := WorldPulse.PERIOD_FACT

## A fixture quest whose single step watches the period. Its grant is a REAL
## authored fate rather than a fixture id, because `DestinyApi.earn_fate` answers a
## fate it cannot resolve by returning the ledger UNCHANGED — so a made-up id would
## have made this suite green against a grant that silently paid nothing. The item
## grant is not an option at all: `QuestGrants.pay` refuses one on an actor with no
## items dependency.
const WATCHED := &"t_period_watcher"
const GRANTED_FATE := &"ancestral_debt_unpaid"


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func teardown() -> void:
	QuestFixtureCatalog.teardown()
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
		SeamHarness.live = null


## The real composition root, mounted under the tree root by the harness — not an
## instance a test called `_ready()` on by hand, which is the detached scene that
## made the previous version of `test_item_workbench_app.gd` measure nothing.
func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## Install a quest that watches the world's period, on the MOUNTED app's actor, and
## accept it. Everything after this is the chain moving on its own.
func _accept_watcher(harness: SeamHarness) -> Actor:
	QuestFixtureCatalog.install(
		[
			QuestFixtureCatalog.quest(
				WATCHED,
				QuestDef.KIND_AUTHORED,
				{},
				[{"step_id": &"waited", "fact": PERIOD_FACT, "need": 1}],
				[{"kind": &"fate", "id": GRANTED_FATE, "amount": 1}]
			)
		]
	)
	var actor := harness.actor
	QuestApi.attach(actor)
	var accepted := QuestApi.accept(actor, WATCHED)
	assert_eq(bool(accepted.get("ok", false)), true, "the player can accept the watcher quest")
	return actor


# --- The wiring exists at boot ----------------------------------------------


## THE first link. Before this change the director had zero production instances,
## so `add_sink` / `offer` / `offer_all` were reachable only from a test that built
## its own. Asserted through the app's own `summary()`, because a test that reached
## into the object instead would pass on a root that never built one.
func test_the_mounted_app_registers_both_sinks_on_a_director() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(
		world["sinks"],
		["QuestBeatHandler", "EventBeatSink"],
		"the boot path registered the quest sink FIRST (priority) and the event sink second"
	)
	assert_eq(String(world["period_fact"]), String(PERIOD_FACT), "and the world names its fact")


## The order is not cosmetic: ADR 0117 makes registration order the priority order,
## and a quest step is a specific promise where an event report is the general one.
## Reversed, this goes red naming the swap rather than merely counting differently.
func test_the_quest_sink_is_consulted_before_the_event_sink() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	_accept_watcher(harness)

	harness.app.call("advance_world", 1)

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	var sinks := world["sinks"] as Array
	assert_eq(String(sinks[0]), "QuestBeatHandler", "a fact an active quest watches is the quest's")


## The period owner is attached to the actor the player is actually holding. An
## `event` ledger that exists on some other actor is the vacuous-wiring class ADR
## 0088 measured as "live in authored content and dead in play".
func test_the_world_ledger_is_attached_to_the_mounted_actor() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return

	assert_ne(
		harness.actor.get_module_data(EventApi.MODULE_KEY),
		{},
		"the boot path attached the event module to the player"
	)
	assert_ne(
		harness.actor.get_module_data(QuestApi.MODULE_KEY),
		{},
		"and the quest module, which the registered sink reads"
	)


# --- The chain, end to end --------------------------------------------------


## THE test. One call on the mounted app advances the world; the fact appears in
## the world's memory, a registered sink claims the beat, and the quest completes
## and pays its grant. Nothing here constructs a director or a beat.
func test_one_advance_drives_the_whole_chain_from_period_to_completed_quest() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "nothing has elapsed yet")

	var report := harness.app.call("advance_world", 1) as Dictionary
	assert_eq(bool(report["ok"]), true, "the world advanced: %s" % String(report["reason"]))
	assert_eq(int(report["periods"]), 1, "by exactly the one period the caller named")

	# 1. The beat landed in the world's memory — ONCE.
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 1, "the beat was recorded exactly once")
	assert_eq(
		WorldFact.fact(actor, PERIOD_FACT).since,
		1,
		"`since` is the count at first record, so this is genuinely the first period"
	)

	# 2. A REGISTERED sink claimed it, and the director names which one.
	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(int(world["claimed"]), 1, "a sink claimed the period's beat")
	assert_eq(int(world["offered"]), 1, "and exactly one beat was offered for it")

	# 3. The quest the player is holding completed — from a beat nobody called by hand.
	var summary := QuestApi.summary(actor)
	assert_eq(
		summary["completed"] as Array,
		[String(WATCHED)],
		"the crossing quest completed, and completion is once"
	)
	assert_eq(
		(summary["active"] as Array).size(),
		0,
		"and it left `active`, so the completion was not a second row"
	)

	# 4. Its grant was paid through the fate ledger the app attached.
	var fates := DestinyApi.summary(actor)["fates"] as Dictionary
	var row = fates.get(String(GRANTED_FATE), {})
	assert_eq(
		bool((row as Dictionary).get("held", false)),
		true,
		"the quest's fate grant was paid, so the completion had a consequence"
	)


## A second period records a second occurrence and completes NOTHING, because
## completion is once. This is what makes the first test's `count == 1` meaningful
## rather than a snapshot of a single pull.
func test_a_second_period_records_again_and_completes_nothing_more() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	harness.app.call("advance_world", 1)
	harness.app.call("advance_world", 1)

	assert_eq(WorldFact.count(actor, PERIOD_FACT), 2, "two whole periods are two occurrences")
	assert_eq(
		QuestApi.summary(actor)["completed"] as Array,
		[String(WATCHED)],
		"and the quest was completed by the first of them, not twice"
	)


# --- The period is the caller's, and it is bounded --------------------------


## ADR 0085 and DEF-0111 in one assertion: a frame that elapsed nothing resolves
## nothing and offers nothing. A default of `1` on the accrual would make the world
## move on a timer whether or not any time was owed to it.
func test_a_frame_that_elapsed_nothing_advances_nothing() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	harness.app.call("_process", 0.0)

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(int(world["periods"]), 0, "no whole period elapsed, so none was pulled")
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "and no beat was offered")


## The fractional half of the old pull is GONE, and this is what is left of it.
##
## The property this test used to hold — "a partial period is owed, not spent" — was
## real, but it was a property of `WorldPulse._elapsed`, the fractional carry of a
## SECONDS converter. **There is no real-time clock for the world (ADR 0167,
## ADR 0173)**: idle is frozen, so there is no elapsed time arriving in fractions and
## nothing is owed between one frame and the next. A "partial period" is no longer
## expressible as input, which is the same reason `SaveClock` lost its ratio
## (ADR 0179) — the input that made the old call-count bug unrepresentable is the one
## this test no longer supplies.
##
## ## The property that DOES survive, and is stronger
##
## **Idle is frozen.** Frame after frame after frame, at any `delta` the engine can
## hand a hitch, the world does not move and offers nothing. That is the ADR 0167
## bullet this suite exists to pin, and it is a claim about an ABSENCE, so it has to be
## driven with a large enough delta to be meaningful: a single frame of one hundred
## periods' worth of seconds is what would have converted whole under the old pull.
func test_idle_frames_do_not_move_the_world_at_any_delta() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	for _frame in 3:
		harness.app.call("_process", WorldPulse.PERIOD_SECONDS * 100.0)

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(
		int(world["periods"]), 0, "a thousand periods worth of seconds moved the world by nothing"
	)
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "and no beat was offered for any of it")


## A frame with no delta at all is not a world event either, so `_process(0.0)` is a
## no-op rather than a refusal. This is the case the whole `_elapsed` buffer used to be
## guarding, kept because the guard is still here and a reader will ask.
func test_a_frame_with_no_delta_is_still_not_an_error() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	harness.app.call("_process", 0.0)

	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "nothing elapsed, so nothing was offered")


## Bounded work: **the intent of the old hitch test, kept and tightened.** A caller that
## asks for a thousand periods in ONE call pays for all of them and does so in a BOUNDED
## number of spends, not a thousand iterations.
##
## ## What changed, and why this assertion got STRONGER rather than weaker
##
## It used to read `clampi(count, 0, MAX_PERIODS_PER_PULL)` and assert the world moved
## **8 periods** from a 1000-period ask. That is the silent truncation ADR 0173 refuses
## ("Exceeding the budget FAILS LOUDLY. It never truncates"): a player declaring a long
## retreat got 8 periods, no error, and no budget spend, and the test called it correct.
## The ceiling is now `_advance`'s per-call bound and the DECLARED span goes through
## `TimeLadder.chunks_for`.
##
## So this now asserts the three things that make the fix load-bearing, and each one goes
## red if the clamp ever comes back:
##
##   1. the world moved the WHOLE declared span, not a prefix of it;
##   2. it moved it in at most `MAX_CHUNKS` spends, so the work is bounded by authored
##      data and not by the ask;
##   3. the beats offered are bounded by `EVENT_BUDGET` per spend — a thousand periods
##      cost a handful of beats, which is ADR 0173 (b)'s whole claim.
##
## `game/tests/core/test_time_ladder.gd` pins the SSOT half; this keeps the
## composition-root half, where the player would meet it.
func test_an_enormous_ask_is_paid_in_full_through_a_bounded_chunk_plan() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)
	var ask := 1000

	var report := harness.app.call("advance_world", ask) as Dictionary

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(
		int(world["periods"]),
		ask,
		(
			"the WHOLE declared span moved — a clamp to %d here is the silent truncation"
			% WorldPulse.MAX_PERIODS_PER_PULL
		)
	)
	assert_eq(int(report["periods"]), ask, "and the report says what MOVED, not what was asked")
	# Bounded spends: at most MAX_CHUNKS, and never one per period.
	var offered := WorldFact.count(actor, PERIOD_FACT)
	assert_eq(
		offered <= TimeLadder.MAX_CHUNKS * TimeLadder.EVENT_BUDGET,
		true,
		(
			(
				"a thousand periods cost %d beats, bounded by MAX_CHUNKS x EVENT_BUDGET (%d): "
				% [offered, TimeLadder.MAX_CHUNKS * TimeLadder.EVENT_BUDGET]
			)
			+ "a per-period loop would be 1000"
		)
	)
	assert_eq(
		offered < ask,
		true,
		(
			"and strictly fewer beats than periods — the span says what became possible,"
			+ " the budget what happened"
		)
	)
	assert_eq(
		int(report["periods"]),
		WorldPulse.MAX_PERIODS_PER_PULL,
		"and the report says what MOVED, which is the clamped count, not the ask"
	)
	assert_eq(
		WorldFact.count(actor, PERIOD_FACT),
		int(WorldPulse.MAX_PERIODS_PER_PULL),
		"exactly that many beats were offered, so the ledger matches the report"
	)


## `advance_world(0)` is not a refusal and not a movement: the module's accrual
## verbs refuse a non-positive amount by design, and a caller that asks for no time
## gets no time rather than a default of one.
func test_asking_for_no_period_moves_nothing() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	var report := harness.app.call("advance_world", 0) as Dictionary

	assert_eq(bool(report["ok"]), true, "it is not an error, it is no elapsed time")
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "and nothing accrued")


# --- The world's own ladder, on the same moment -----------------------------


## The world's stage ladder moves on the SAME period the beat accrues on, which is
## the whole point of the composition root owning the moment: `EventApi.advance`
## refuses `periods <= 0`, so with no owner the ladder could never move at all.
##
## The tide is opened by satisfying its authored trigger through the world's own
## memory first, so this asserts the ladder rather than the trigger.
func test_the_world_ladder_is_pulled_by_the_same_period_the_beat_accrues_on() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	EventApi.set_location(actor, &"mortal_plains")
	WorldFact.record(actor, &"storm_front_sighted", 1)

	assert_eq(
		(harness.app.call("world_summary") as Dictionary)["available_events"],
		1,
		"the world's own trigger now admits exactly the beast tide"
	)
	harness.app.call("advance_world", 1)

	var world := (harness.app.call("world_summary") as Dictionary) as Dictionary
	assert_eq(int(world["active_events"]), 1, "the composition root opened it")
	assert_eq(int(world["world_period"]), 1, "and the world's own period counter moved")
	assert_eq(
		WorldFact.count(actor, &"beast_tide_started"),
		1,
		"the tide's authored opening beat is in the world's memory"
	)
	assert_eq(
		int(world["module_recorded_facts"]),
		2,
		(
			"and the two facts the module recorded for itself are COUNTED, not re-offered: "
			+ "`WorldFact.record` is monotone, so offering them again would write one "
			+ "occurrence twice"
		)
	)


## A period is the world's own accrual and nothing else: it must not double-count
## the facts the event module already wrote. This is the assertion that fails if a
## future change offers `module_recorded_facts` to the director as well.
func test_the_period_does_not_re_offer_the_facts_the_module_already_recorded() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	EventApi.set_location(actor, &"mortal_plains")
	WorldFact.record(actor, &"storm_front_sighted", 1)
	harness.app.call("advance_world", 1)

	assert_eq(WorldFact.count(actor, &"beast_tide_started"), 1, "the opening fact, once")
	assert_eq(WorldFact.count(actor, &"beast_tide_moving"), 1, "the stage fact, once")
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 1, "and the period's own beat, once")
