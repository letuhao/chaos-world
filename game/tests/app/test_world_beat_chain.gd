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
## [code]ItemWorkbenchApp._ready[/code] wired it and the app's own `_process`
## advanced it.
##
## ## What "the chain is live" means here, precisely
##
##   `_process(delta)` -> `WorldPulse.pull` -> a whole period elapses
##     -> `EventApi.advance(actor, periods)`  (the world's own ladder)
##     -> a beat minted by the OWNER OF THE MOMENT
##        -> `BeatDirector.offer` -> `WorldFact.record`
##        -> `QuestBeatHandler.handles` -> `QuestApi.advance` -> quest completed
##
## Removing any link turns one of the assertions below red, and each mutation was
## run and observed.

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


## The elapsed-time half of the tick, driven through the app's OWN `_process` — the
## one tick caller in the game. A partial period is owed, not spent.
func test_elapsed_time_accrues_a_period_only_once_it_is_whole() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	harness.app.call("_process", WorldPulse.PERIOD_SECONDS * 0.5)
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 0, "half a period is owed, not spent")

	harness.app.call("_process", WorldPulse.PERIOD_SECONDS * 0.5)
	assert_eq(WorldFact.count(actor, PERIOD_FACT), 1, "the other half completes one period")


## A hitch is bounded. One enormous delta is clamped rather than converted, so a
## breakpoint cannot walk an authored event ladder to its end in a single frame — and
## the surplus is dropped rather than banked, because a banked surplus pays out later
## at a rate nobody chose.
func test_one_enormous_delta_is_clamped_rather_than_converted() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := _accept_watcher(harness)

	harness.app.call("_process", WorldPulse.PERIOD_SECONDS * 1000.0)

	var world := (harness.app.summary() as Dictionary)["world"] as Dictionary
	assert_eq(
		int(world["periods"]),
		WorldPulse.MAX_PERIODS_PER_PULL,
		"a hitch is clamped to the ceiling, not converted whole"
	)
	assert_eq(
		WorldFact.count(actor, PERIOD_FACT),
		int(WorldPulse.MAX_PERIODS_PER_PULL),
		"and exactly that many beats were offered, so the ledger matches the report"
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
