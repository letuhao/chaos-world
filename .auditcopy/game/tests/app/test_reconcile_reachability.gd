extends TestCase

## ADR 0170 (a world advances in stages and a stage marks stale what it did not
## reconcile) trigger (a), and ADR 0173 (c) (a place advances when observed).
## `core/world_reconcile.gd`, `core/reconcile_stamp.gd` and `core/world_epoch.gd` were
## built, exported and tested with **zero production callers** — the unwired-primitive
## defect (ADR 0134), the highest-priority failure class because the code works and no
## player can reach it.
##
## ## THE RULE THIS FILE FOLLOWS: NEVER DRIVE THE THING UNDER TEST
##
## Nothing here constructs a `WorldReconcile`, folds a stamp, or calls `observe` to
## produce the answer it then asserts. Every figure below is reached the way a player's
## arrival reaches it, through the SAME seam the composition root installs:
##
## ```
## WorldStage.stand_in_the_tree(body)      # what CharacterCreationProgram:228 calls
## WorldStage.mount(body, location_id)     # ...then :229. item_workbench_body.gd:547 too.
##   -> WorldStage._observe_place          # app/world_stage.gd
##     -> WorldPulse.observe_place         # the Callable item_workbench_app.gd:357 installs
##       -> WorldReconcile.observe         # the core mechanism, reached from above
## ```
##
## A suite that builds `WorldReconcile` and calls it proves the mechanism works. This
## one proves **a player can reach it** — the difference
## `test_retreat_costs_world_time.gd:89` (`test_the_mounted_composition_root_answers_a_retreat`)
## was written to close, for the same reason and on the same principle.
##
## ## Why this drives `mount` rather than mounting the app
##
## `ItemWorkbenchApp` is mid-split by concurrent sessions and may fail to parse, so a
## mount-based proof here would measure another agent's half-finished edit rather than
## ADR 0170. **`WorldStage.mount` IS the production entry** — `character_creation_program.gd:229`
## and `item_workbench_body.gd:547` are its two callers and both are production paths —
## so driving it here exercises the shipped chain end to end. The composition root's own
## contribution (installing the two `Callable`s) is asserted separately, from SOURCE, by
## `test_the_composition_root_installs_both_adr_0170_seams`, because that line is what
## makes `mount`'s fold reachable at all and it is exactly the line a future edit could
## delete. Source-reading is the shape `test_realm_rate.gd:208-224` and
## `test_time_ladder.gd:386-401` both use, and for the same measured reason: a numerically
## identical private copy stays green under every value assertion.

## The authored location this suite arrives at. Read from the SHIPPED pool rather than
## typed, so a retune of `game/data/world/locations/*.tres` cannot make the arrival fail
## in a way that reads as a wiring defect.
const ARRIVAL := &"mortal_plains"
## A second authored place nobody has visited, for the per-place half of ADR 0170.
const UNVISITED := &"spirit_peaks"
## The place-fact the ledger half of the epoch reader records, and the world's own id.
const TEMPLE := &"founded_temple"
const LOWER_REALM := &"lower_realm"

const STAGE_SRC := "res://src/app/world_stage.gd"
const PULSE_SRC := "res://src/app/world_pulse.gd"
const ROOT_SRC := "res://src/app/item_workbench_app.gd"

var _actor: Actor = null
var _pulse: WorldPulse = null
var _body: PlayerAdapter = null
var _stage: WorldStage = null
var _saved_reconciler: Callable = Callable()
var _saved_epoch_reader: Callable = Callable()


## A coarse span in the SSOT's own authored units, resolved through `ratio_for` rather
## than written as a literal, for the reason `test_retreat_costs_world_time.gd:59`
## gives: a literal silently drifts out of the ladder's vocabulary when the ladder is
## retuned, and every assertion about a crossed year then compares 0 against 1.
static func coarse_span() -> int:
	return TimeLadder.ratio_for(&"year")


func setup() -> void:
	_actor = Actor.new(&"reconcile_hero")
	_pulse = WorldPulse.new(_actor, BeatDirector.new())
	_body = PlayerAdapter.new(_actor)
	_stage = WorldStage.new()
	# **The seams are installed EXACTLY as `item_workbench_app.gd` installs them**, on the
	# REAL fold rather than a stand-in. Installing a local closure instead would make the
	# production line `set_reconciler(Callable(_world, "observe_place"))` untested, which
	# is the line that made this mechanism unreachable in the first place.
	_saved_reconciler = Callable()
	_saved_epoch_reader = Callable()
	WorldStage.set_reconciler(Callable(_pulse, "observe_place"))
	WorldStage.set_epoch_reader(Callable(_pulse, "place_state"))


func teardown() -> void:
	# The mounted body is a PROCESS-WIDE static, so a stage left behind publishes a freed
	# `PlayerAdapter` to every suite that runs after this one.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	WorldStage.release_the_tree(_body)
	_body = null
	_stage = null
	_pulse = null
	_actor = null
	# Cleared rather than left pointing at this suite's fold: `_reconciler` is static, and
	# a suite that left it installed would make the next suite's arrival reconcile against
	# a pulse whose actor is gone. The `set_*` docstrings promise a null clears it.
	WorldStage.set_reconciler(_saved_reconciler)
	WorldStage.set_epoch_reader(_saved_epoch_reader)


## Stand the body in the tree and ARRIVE, through the production chain. `mount` is what
## `character_creation_program.gd:229` and `item_workbench_body.gd:547` both call, so this
## is the shipped arrival rather than a lookalike of it.
func _arrive(location_id: StringName = ARRIVAL) -> Dictionary:
	WorldStage.stand_in_the_tree(_body)
	return _stage.mount(_body, location_id)


## Move the world by `count` periods through the REAL fold verb a player action drives
## (`ItemWorkbenchPlay.advance_world` is a thin pass-through to this). It is the fold's
## own period total that an observation is later measured against, which is the whole of
## why `observe_place` takes no span argument.
func _advance(count: int) -> Dictionary:
	return _pulse.advance_periods(count)


# --- 1. THE PRODUCTION CALLERS EXIST -------------------------------------------


## ## ACCEPTANCE CRITERION 1: `WorldReconcile`, `ReconcileStamp` and `WorldEpoch` each
## have at least ONE production caller under `game/src/`.
##
## ## Asserted from SOURCE, and that choice is load-bearing.
##
## The audit's finding was "an exhaustive grep excluding `src/core` and `tests` returns
## nothing", so the claim being made here is EXACTLY a claim about what `src/` contains
## and no runtime assertion can make it — a mechanism reached from a test is green and
## unreachable. Read from source rather than typed, so deleting one of the three call
## lines turns this red rather than leaving a suite that still passes.
func test_all_three_core_files_have_a_production_caller() -> void:
	var pulse := _code_only(FileAccess.get_file_as_string(PULSE_SRC))
	var stage := _code_only(FileAccess.get_file_as_string(STAGE_SRC))
	assert_ne(pulse, "", "%s is readable" % PULSE_SRC)
	assert_ne(stage, "", "%s is readable" % STAGE_SRC)
	# `WorldReconcile` — the fold, and the summary `tools ui drive` prints.
	assert_eq(
		pulse.contains("WorldReconcile.observe("), true, "WorldPulse.observe_place folds"
	)
	assert_eq(pulse.contains("WorldReconcile.summary("), true, "and WorldPulse.summary reads")
	# `ReconcileStamp` — the store the fold writes, read back for a place's date.
	assert_eq(pulse.contains("ReconcileStamp.empty()"), true, "the stamp set is the empty one")
	assert_eq(
		pulse.contains("ReconcileStamp.folded_periods("), true, "and a place's age is read from it"
	)
	# `WorldEpoch` — the overlay, from both sides: the fold holds the set and the reader
	# derives a place's current state from (ledger, epoch).
	assert_eq(pulse.contains("WorldEpoch.empty()"), true, "the epoch set is the empty one")
	assert_eq(pulse.contains("WorldEpoch.state_of("), true, "and state_of is the reader")
	assert_eq(
		stage.contains("WorldEpoch.FIRST"), true, "WorldStage reads the epoch through WorldEpoch"
	)


## ## The composition root is what makes `mount`'s fold reachable, so its two
## `set_*` lines are asserted directly.
##
## `_ready` installs them and `adopt_actor` RE-POINTS them, because both name a
## `WorldPulse` and a rebirth replaces that object — the same reason the offer resolver
## and the location publisher are re-pointed there. Asserted on the SOURCE because
## `ItemWorkbenchApp` may fail to parse while other sessions split it, and a source
## assertion measures the wiring line rather than the mounting.
func test_the_composition_root_installs_both_adr_0170_seams() -> void:
	var root := _code_only(FileAccess.get_file_as_string(ROOT_SRC))
	assert_ne(root, "", "%s is readable" % ROOT_SRC)
	assert_eq(
		root.contains("WorldStage.set_reconciler(Callable(_world, \"observe_place\"))"),
		true,
		"the root installs the reconcile seam, so an arrival folds rather than silently rotting"
	)
	assert_eq(
		root.contains("WorldStage.set_epoch_reader(Callable(_world, \"place_state\"))"),
		true,
		"and the epoch reader, so a place's current state has a production resolver"
	)
	# BOTH sites, not one: `adopt_actor` rebuilds `_world`, so a seam installed only at
	# `_ready` would name the FALLEN hero's fold — a live call with a dead owner, which is
	# the half-swapped-body failure that method exists to prevent.
	assert_eq(
		root.count("WorldStage.set_reconciler("), 2, "installed at boot and re-pointed on rebirth"
	)
	assert_eq(
		root.count("WorldStage.set_epoch_reader("), 2, "and the epoch reader is too"
	)


## The seam is a `Callable` and this file names no clock type. `set_location_publisher`'s
## contract is what keeps `test_the_stage_does_not_import_quest_or_event` true, and this
## is the same rule one level down: a stage that held a `WorldPulse` would couple the
## arrival to the fold and make the seam pointless.
func test_the_stage_reaches_the_clock_only_through_a_callable() -> void:
	assert_eq(WorldStage.has_reconciler(), true, "the seam is installed for this suite")
	assert_eq(WorldStage.has_epoch_reader(), true, "and so is the epoch reader")
	var stage := _code_only(FileAccess.get_file_as_string(STAGE_SRC))
	assert_eq(stage.contains("WorldPulse"), false, "WorldStage names no world fold at all")
	assert_eq(stage.contains("WorldReconcile."), false, "and folds nothing itself")
	# It DOES reach `core`, through `WorldEpoch.FIRST` — the floor an unrebuilt world
	# reads. That is a CONSTANT read, not a ledger, which is what `app/` holding no
	# ledger permits.
	assert_eq(stage.contains("WorldFact.count("), false, "and never rewrites the ledger")


# --- 2. REACHABILITY: the arrival moves the stamp -------------------------------


## ## THE CLAIM THIS SUITE EXISTS FOR.
##
## A player arrives somewhere, the world clock has moved, and the PLACE'S OWN CLOCK moves
## with it — measured on the fold's own published read model, not on a number this suite
## computed. `WorldPulse.summary()["reconciled"]` is `WorldReconcile.summary(_stamps)`,
## so a stamp that never moved reports zero places here and cannot pass.
func test_arriving_at_a_place_ages_that_place() -> void:
	# The world moves FIRST, with nobody standing anywhere. Nothing may happen to a
	# place in this gap — that is ADR 0170's "nothing ticks while nobody is there", and
	# asserting it is what makes the assertion below mean something.
	_advance(coarse_span())
	assert_eq(
		int(_pulse.summary()["reconciled"]["places"]), 0, "no place is stale before anyone arrives"
	)

	var arrival := _arrive(ARRIVAL)

	assert_eq(
		bool(arrival.get("ok", false)), true, "the production arrival succeeded: %s" % arrival.get("reason", "")
	)
	var folded := _pulse.summary()["reconciled"] as Dictionary
	assert_eq(
		int(folded.get("places", 0)),
		1,
		"one place carries a stamp after one arrival, and it is read off the fold's own summary"
	)
	assert_eq(
		int(folded.get("total_periods_folded", 0)),
		coarse_span(),
		"and it folded the WHOLE span the world had moved. A reconcile that truncates to a cap reports nothing the player can see (ADR 0170)"
	)


## The chain is a CHAIN, not one link: the arrival's OWN answer carries the age, so a
## player or a panel reading only the arrival — which is what `mount` returns and what
## `on_location_selected` forwards to a map screen — can see how far behind the world was
## without reaching into the fold.
func test_the_arrival_reports_the_place_age_it_folded() -> void:
	_advance(coarse_span())
	var arrival := _arrive(ARRIVAL)
	assert_eq(
		bool(arrival.get("reconciled", false)),
		true,
		"the arrival says it reconciled: %s" % arrival.get("reconciled_reason", "")
	)
	assert_eq(
		int(arrival.get("reconciled_periods", 0)),
		coarse_span(),
		"and reports the span it paid for, on the answer a map screen reads"
	)
	assert_eq(
		int(arrival.get("place_periods", 0)),
		coarse_span(),
		"plus the place's folded age, which is what a panel prints as the place's date"
	)


## ## The stage's OWN read model carries it, because `summary()` is the UI contract.
##
## ADR 0038: a screen's `summary()` is primitives all the way down, so this asserts the
## flattened scalars rather than reaching for a nested dictionary a panel would read as
## `null`.
func test_the_stage_summary_reports_the_reconcile_seams_health() -> void:
	_advance(coarse_span())
	_arrive(ARRIVAL)
	var stage_summary := _stage.summary()
	assert_eq(bool(stage_summary["reconciler_installed"]), true, "the reconciler seam is installed")
	assert_eq(bool(stage_summary["epoch_reader_installed"]), true, "and the epoch reader")
	assert_eq(bool(stage_summary["reconciled"]), true, "the place reconciled")
	assert_eq(
		String(stage_summary["reconciled_reason"]),
		"",
		"with no refusal to explain, rather than a silent zero (ADR 0170)"
	)
	assert_eq(
		int(stage_summary["place_periods"]), coarse_span(), "and the folded age is on the summary"
	)


## The place nobody stands in does NOT move, and re-arriving does not re-fold the world.
## Both halves of ADR 0170's fold rule, and the second is what "a place returning to
## scope is FOLDED, never replayed" buys: a stamp keyed by a period watermark would pay
## the span a second time on every visit.
func test_a_place_moves_only_when_it_is_observed_and_never_pays_twice() -> void:
	_advance(coarse_span())
	_arrive(ARRIVAL)
	_advance(coarse_span())

	# Nobody has been to the second place at all, and it is still stale at zero.
	var summary := _pulse.summary()["reconciled"] as Dictionary
	assert_eq(
		int(summary.get("places", 0)), 1, "a place nobody stood in is not stamped by another place's arrival"
	)
	assert_eq(
		int(summary.get("total_periods_folded", 0)),
		coarse_span(),
		"and its date is untouched: one place advancing does not age the world"
	)

	# Now ARRIVE there, through the production chain again.
	var arrival := _arrive(UNVISITED)
	assert_eq(bool(arrival.get("ok", false)), true, "the second arrival succeeded")
	assert_eq(
		int(arrival.get("reconciled_periods", 0)),
		coarse_span() * 2,
		(
			"its first arrival folds the WHOLE span the fold has moved. A reconcile gated on "
			+ "'have I been here' would report zero here — that is the ADR 0173 (c) deadlock"
		)
	)
	assert_eq(
		int(_pulse.summary()["reconciled"]["places"]), 2, "and now two places carry a stamp"
	)


## `WorldReconcile.shipped_locations` has a production reader on the same path a player
## reaches, and the four shipped `.tres` are the scope identity ADR 0170 keys on. Not
## "the reconcile covers everything" — the stamp is per-place by design — but that the
## ARRIVAL'S place is one of the authored ids rather than an arbitrary string, which is
## what makes the stamp keyable across a save.
func test_the_arrival_place_is_an_authored_scope_identity() -> void:
	var authored := WorldReconcile.shipped_locations()
	assert_eq(authored.is_empty(), false, "the authored world ships locations")
	assert_eq(
		authored.has(ARRIVAL), true, "%s is an authored location_id (ADR 0170's scope identity)" % ARRIVAL
	)


# --- 3. THE DEADLOCK HAZARD, PINNED ---------------------------------------------


## ## THE HAZARD (ADR 0173 (c)), verbatim:
##
## "an observation-driven clock DEADLOCKS if every advance source is itself gated on
## someone being present. The world freezes forever, every elapsed calculation returns
## zero, and the failure is silent — nothing errors, everything is simply always zero."
##
## **The rule is: ANY observation advances FIRST, then reads. A reader is a trigger,
## never a precondition of the trigger.** There must be no `if visited: fold()`, and
## `WorldPulse.observe_place` carries that requirement in its own docstring for the same
## reason `WorldReconcile`'s class docstring does.
##
## **THE ASSERTION IS ABOUT THE ORDER, NOT ABOUT A PLACE.** Every reachability test above
## arrives at a place, and an arrival is a presence event — so all of them would still
## pass against a reconcile written as `if someone_is_here: fold()`. This case reads a
## place NOBODY has ever visited and demands a NON-ZERO elapsed. A gate cannot pass it,
## because a gate is false for precisely that place. If a future "skip the fold we have
## already done" optimisation ever lands on this path, this goes red — which is the only
## reason it exists, and it must never be softened.
func test_a_read_on_a_never_visited_place_still_returns_non_zero_elapsed() -> void:
	_advance(coarse_span())
	# Nobody has arrived anywhere: `_arrive` is deliberately NOT called.
	assert_eq(
		int(_pulse.summary()["reconciled"]["places"]), 0, "nothing has been observed at all"
	)

	var seen := _pulse.observe_place(UNVISITED)

	assert_eq(
		int(seen.get("elapsed_periods", 0)),
		coarse_span(),
		(
			"a place nobody has stood in still reports the WHOLE span as elapsed. A fold "
			+ "gated on presence answers zero here, and every later read is silent zero too — "
			+ "the world freezes with nothing erroring (ADR 0173 (c))"
		)
	)
	assert_eq(
		int(seen.get("elapsed_periods", 0)) > 0,
		true,
		"stated as a bare non-zero so the point survives an edit to the sentence above"
	)
	assert_eq(
		bool(seen.get("advanced", false)), true, "and the observation advanced the place's clock"
	)
	assert_eq(
		int(seen.get("folded_periods", 0)),
		coarse_span(),
		"so the place's own read model carries a date nobody has to be standing there for"
	)


## The freeze is SILENT, so it has to be pinned on the read model too: a clock that
## returned zero would still answer `ok`, and a panel reading `places` rather than a
## failure would print a world where nothing had ever happened. Asserted on the fold's
## published summary, which is the dictionary `tools ui drive` prints with no display.
func test_the_read_model_reports_the_fold_a_panel_would_print() -> void:
	_advance(coarse_span())
	_pulse.observe_place(UNVISITED)
	var reconciled := _pulse.summary()["reconciled"] as Dictionary
	assert_eq(int(reconciled.get("places", 0)), 1, "the read stamped the unvisited place")
	assert_eq(
		int(reconciled.get("total_periods_folded", 0)),
		coarse_span(),
		"with its whole span, printed with no display at all"
	)
	assert_eq(
		int(reconciled.get("cap", 0)), WorldReconcile.MAX_PLACES, "and the cap a pass folds against"
	)
	assert_eq(
		int(reconciled.get("event_budget", 0)),
		TimeLadder.EVENT_BUDGET,
		"and the SSOT's event budget, so the read model names the clock it is reading"
	)


## ## And the freeze cannot be built out of ORDERING either.
##
## A fold that lowered anything, or a reader that answered from a pre-fold read, would
## let two observations in the wrong order make a place look LESS folded — which is the
## decrement ADR 0113's monotone ledger exists to forbid. So an EARLY observation is
## re-taken after a LATER one and must not move the date backwards.
func test_an_early_observation_does_not_move_a_later_one_backwards() -> void:
	_advance(coarse_span())
	_pulse.observe_place(ARRIVAL)
	var after_first := ReconcileStamp.folded_periods(
		_pulse.summary()["stamps"] as Dictionary, ARRIVAL
	)
	_advance(coarse_span())
	_pulse.observe_place(ARRIVAL)
	var after_second := ReconcileStamp.folded_periods(
		_pulse.summary()["stamps"] as Dictionary, ARRIVAL
	)
	assert_eq(after_second > after_first, true, "a later observation raises the place's fold")
	# The OLD span, re-offered. `ReconcileStamp.fold_all` is a MAX, so this cannot lower.
	_pulse.observe_place(ARRIVAL)
	var after_replay := ReconcileStamp.folded_periods(
		_pulse.summary()["stamps"] as Dictionary, ARRIVAL
	)
	assert_eq(
		after_replay, after_second, "re-offering an older span moves no fold backwards (ADR 0113)"
	)


# --- 4. THE EPOCH OVERLAY HAS A PRODUCTION READER -------------------------------


## ## `WorldEpoch.state_of` is reached through the stage's `place_state`, so a retired
## world's occurrences STAY on the ledger while a successor reads the history it is
## actually living.
##
## The overlay is a READ, so this needs no arrival: `place_state` is answerable for any
## place at any moment, which is exactly why it is a separate seam from the reconciler.
## A suite that only read the epoch on arrival would pass while a panel asking about a
## place nobody is standing in got nothing — the ADR 0173 (c) freeze in read-only form.
func test_the_epoch_reader_answers_without_anybody_arriving() -> void:
	# The world is rebuilt: the old world RETIRED, the successor carrying the next epoch.
	_pulse.retire_world(LOWER_REALM, &"rebuilt_realm")
	var stage := WorldStage.new()
	stage.enter(_actor)
	var state := stage.place_state(
		[
			{"id": "founded_temple", "epoch": 1, "amount": 1},
			{"id": String(TEMPLE), "epoch": WorldEpoch.FIRST, "amount": 2},
		]
	)
	assert_eq(
		int(state.get("epoch", 0)),
		WorldEpoch.current(WorldEpoch.empty(), &"rebuilt_realm"),
		"the overlay's own epoch answer reaches the stage through the installed seam"
	)
	assert_eq(
		(state.get("applied", []) as Array).size(),
		2,
		"and both occurrences applied at the epoch the reader resolves against"
	)


## ## A retired world reads its OWN history and a successor reads the newer one, with
## nothing un-recorded. That is the whole of ADR 0170's epoch, and it is asserted on the
## ledger AFTER the read, so the overlay cannot pass by withdrawing a fact.
func test_a_retired_worlds_history_is_rewritten_without_un_recording_anything() -> void:
	_pulse.retire_world(LOWER_REALM, &"rebuilt_realm")
	var stage := WorldStage.new()
	stage.enter(_actor)
	var occurrences := [
		{"id": "lower_realm_founded", "epoch": 1, "amount": 1},
		{"id": "rebuilt_realm_founded", "epoch": 2, "amount": 1},
	]
	# The ledger records BOTH, on the one monotone row, BEFORE either is read.
	WorldFact.record(_actor, &"lower_realm_founded", 1)
	WorldFact.record(_actor, &"rebuilt_realm_founded", 1)

	var retired := stage.place_state(occurrences)
	assert_eq(
		bool(retired.get("retired", false)), true, "the rebuilt world reads as retired"
	)
	assert_eq(
		int((retired.get("counts", {}) as Dictionary).get("lower_realm_founded", 0)),
		1,
		"and sees the founding that happened during the epoch it lived"
	)
	assert_eq(
		(retired.get("deferred", []) as Array),
		["rebuilt_realm_founded"],
		"while NAMING the later occurrence as not-yet, so a reader can tell it from one that never existed"
	)
	# THE MONOTONE HALF, asserted on the ledger itself rather than on the overlay.
	assert_eq(
		WorldFact.count(_actor, &"lower_realm_founded"), 1, "the retired world's founding is still recorded"
	)
	assert_eq(
		WorldFact.count(_actor, &"rebuilt_realm_founded"), 1, "and so is the successor's"
	)
	assert_eq(
		WorldFact.count(_actor, &"lower_realm_founded") > 0,
		true,
		"nothing was un-recorded by the rebuild (ADR 0113)"
	)


## The epoch overlay's floor is a constant of `core`, not a guess, and an unrebuilt world
## must answer epoch one rather than a refusal: "this world was never rebuilt" and
## "nothing can answer" must not be the same reading, because a panel reading the first
## as the second hides a wiring gap behind a plausible date.
func test_the_stage_answers_the_first_epoch_for_a_world_nobody_rebuilt() -> void:
	var stage := WorldStage.new()
	stage.enter(_actor)
	assert_eq(
		stage.place_epoch(),
		WorldEpoch.FIRST,
		"a world nobody rebuilt reads as epoch one (ADR 0170)"
	)


# --- 5. THE SEAM'S OWN REFUSALS ARE NAMED ---------------------------------------


## A stage with NO reconcile seam still arrives, and SAYS the place is unwired. The
## posture is `_publish_location`'s: the player really did travel, `world_spawn`'s
## ledger is the durable truth, and the gap is reported rather than swallowed — a silent
## reconcile is indistinguishable from a frozen world, which is the failure this whole
## wiring exists to remove.
func test_an_arrival_with_no_reconciler_arrives_and_names_the_gap() -> void:
	WorldStage.set_reconciler(Callable())
	assert_eq(WorldStage.has_reconciler(), false, "the seam really is uninstalled")
	_advance(coarse_span())
	var arrival := _arrive(ARRIVAL)
	assert_eq(
		bool(arrival.get("ok", false)), true, "the arrival still succeeded without the seam"
	)
	assert_eq(
		String(arrival.get("reconciled_reason", "")),
		"no_reconciler",
		"and names the wiring gap instead of reporting a clean zero fold"
	)
	assert_eq(
		int(arrival.get("reconciled_periods", 0)), 0, "no fold happened, and the answer says so"
	)


## `leave` drops the stage's own answer but does NOT undo the stamp, and that asymmetry
## is the point: the stamp is monotone and the world fold owns it, so the next arrival
## reads how far behind the world really is instead of folding the same span twice.
func test_leaving_drops_the_answer_and_keeps_the_stamp() -> void:
	_advance(coarse_span())
	_arrive(ARRIVAL)
	var stamps := _pulse.summary()["stamps"] as Dictionary
	var folded_before := ReconcileStamp.folded_periods(stamps, ARRIVAL)

	var left := _stage.leave()
	assert_eq(bool(left.get("ok", false)), true, "the stage left cleanly")
	assert_eq(
		String(_stage.summary()["reconciled_reason"]),
		"left",
		"and reports no standing reconcile rather than the previous place's answer"
	)
	var stamps_after := _pulse.summary()["stamps"] as Dictionary
	assert_eq(
		ReconcileStamp.folded_periods(stamps_after, ARRIVAL),
		folded_before,
		"while the stamp itself is untouched — leaving is not un-recording (ADR 0173)"
	)


# --- Internals -----------------------------------------------------------------


## Whole-line comments, trailing comments and `"""` blocks removed before a scan, so a
## guard reading these files cannot fire on their own prose. The shape is
## `test_reconcile_stamp.gd:697`'s, borrowed unchanged and for its stated reason.
func _code_only(source: String) -> String:
	var kept: Array[String] = []
	for raw in source.split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line.substr(0, maxi(0, line.find("#"))))
	return "\n".join(kept)