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
## The place-fact the ledger half of the epoch reader records.
const TEMPLE := &"founded_temple"

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
	# ## THE ORDER HERE IS LOAD-BEARING, AND IT IS A CORRECTNESS REQUIREMENT FOR THE
	# ## WHOLE RUNNER, NOT FOR THIS SUITE.
	#
	# `WorldStage.stand_in_the_tree` mints an authored `WorldEntry` parented under `root`
	# and hands it back, and it is a PROCESS-WIDE static keyed by node name. If that entry
	# is left standing, the next `stand_in_the_tree` finds the body already parented and
	# returns it as `reused` without re-parenting — and the mount that follows then runs
	# against an entry a PREVIOUS suite's teardown is about to free. Measured, not inferred:
	# leaving the tree behind produced `Can't add child 'WorldStagePlayer' … already has a
	# parent` and then a cascade of failures in `tests/core/test_reconcile_stamp.gd`, which
	# is three suites away and shares no code with this one.
	#
	# So: leave the stage FIRST, so `_current` and `_mounted_player` are cleared, and
	# release the tree SECOND, through `WorldStage.release_the_tree` — the production
	# `free()`-not-`queue_free()` path whose docstring names the leaked subtree.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if is_instance_valid(_body):
		WorldStage.release_the_tree(_body)
	_body = null
	# **Seams cleared LAST and ALWAYS**, including by the cases that uninstalled them
	# themselves: `_reconciler` and `_epoch_reader` are statics, and one left pointing at
	# this suite's fold would make the next suite's arrival reconcile against a pulse
	# whose actor is gone. `set_reconciler`'s own docstring promises a null clears it.
	WorldStage.set_reconciler(_saved_reconciler)
	WorldStage.set_epoch_reader(_saved_epoch_reader)
	_stage = null
	_pulse = null
	_actor = null


## Stand the body in the tree and ARRIVE, through the production chain. `mount` is what
## `character_creation_program.gd:229` and `item_workbench_body.gd:547` both call, so this
## is the shipped arrival rather than a lookalike of it.
##
## **The previous entry is released FIRST.** `stand_in_the_tree` is idempotent by node
## NAME, so a second arrival inside one case finds the body still parented and answers
## `reused` — the arrival then reads the FIRST place's stamp and the second place never
## folds, which is a false negative about ADR 0170 rather than a defect in it. A case
## that arrives twice is a case asking two questions of one world, so it gets a clean
## world each time.
func _arrive(location_id: StringName = ARRIVAL) -> Dictionary:
	if is_instance_valid(_body) and _body.get_parent() != null:
		WorldStage.release_the_tree(_body)
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
	assert_eq(pulse.contains("WorldReconcile.observe("), true, "WorldPulse.observe_place folds")
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
		root.contains('WorldStage.set_reconciler(Callable(_world, "observe_place"))'),
		true,
		"the root installs the reconcile seam, so an arrival folds rather than silently rotting"
	)
	assert_eq(
		root.contains('WorldStage.set_epoch_reader(Callable(_world, "place_state"))'),
		true,
		"and the epoch reader, so a place's current state has a production resolver"
	)
	# BOTH sites, not one: `adopt_actor` rebuilds `_world`, so a seam installed only at
	# `_ready` would name the FALLEN hero's fold — a live call with a dead owner, which is
	# the half-swapped-body failure that method exists to prevent.
	assert_eq(
		root.count("WorldStage.set_reconciler("), 2, "installed at boot and re-pointed on rebirth"
	)
	assert_eq(root.count("WorldStage.set_epoch_reader("), 2, "and the epoch reader is too")


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
		bool(arrival.get("ok", false)),
		true,
		"the production arrival succeeded: %s" % arrival.get("reason", "")
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
		(
			"and it folded the WHOLE span the world had moved. A reconcile that truncates "
			+ "to a cap reports nothing the player can see (ADR 0170)"
		)
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
		int(summary.get("places", 0)),
		1,
		"a place nobody stood in is not stamped by another place's arrival"
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
	assert_eq(int(_pulse.summary()["reconciled"]["places"]), 2, "and now two places carry a stamp")


## ## `enter` is the HEADLESS half of a mount and must age the place identically.
##
## The docstring above it says so — "a caller driving the game with no scene tree must
## reach exactly the same events as one with a body" — and until now that claim covered
## only the event publish. A reconcile wired into `mount` alone would leave every headless
## driver, probe and replay ageing a place the graphical path ages and no other, so the
## mechanism would look live in one world and be inert in the other.
func test_the_headless_door_folds_the_place_too() -> void:
	# `WorldSpawnApi.selected` is what `mount` itself calls to put the actor somewhere, so
	# `enter`'s own `WorldSpawnApi.current` precondition is satisfied by production code.
	var placed := WorldSpawnApi.selected(_actor, ARRIVAL)
	assert_eq(bool(placed.get("ok", false)), true, "the actor is located by the durable verb")
	_advance(coarse_span())

	var entered := _stage.enter(_actor)

	assert_eq(bool(entered.get("ok", false)), true, "the headless arrival succeeded")
	assert_eq(
		int(entered.get("reconciled_periods", 0)),
		coarse_span(),
		"and folded the whole span, exactly as a mount through a body would"
	)
	assert_eq(
		int(_pulse.summary()["reconciled"]["total_periods_folded"]),
		coarse_span(),
		"on the fold's own read model, so the two doors cannot disagree"
	)


## ## Re-entering a place pays for what ELAPSED SINCE, not what it has already folded.
##
## This is "a place returning to scope is FOLDED, never replayed" (ADR 0170), and it is
## the negative half of the deadlock guard: the rule is advance-FIRST-then-read, not
## advance-every-time. `ReconcileStamp.fold_all` is a MAX, so a second arrival with no
## time between them folds nothing.
func test_re_entering_a_place_pays_only_for_what_elapsed_since() -> void:
	_advance(coarse_span())
	_arrive(ARRIVAL)
	# Immediately again: no world time has passed, so there is nothing to pay for.
	var again := _arrive(ARRIVAL)
	assert_eq(
		int(again.get("reconciled_periods", 0)),
		0,
		"a second arrival with no elapsed time pays nothing (ADR 0170: folded, never replayed)"
	)
	# And after real time, the same place pays for exactly the NEW span and no more.
	_advance(coarse_span())
	var later := _arrive(ARRIVAL)
	assert_eq(
		int(later.get("reconciled_periods", 0)),
		coarse_span(),
		"the newly elapsed span, not the whole accumulated one"
	)
	assert_eq(
		int(later.get("place_periods", 0)),
		coarse_span() * 2,
		"while the place's own date is the total it has folded across both arrivals"
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
		authored.has(ARRIVAL),
		true,
		"%s is an authored location_id (ADR 0170's scope identity)" % ARRIVAL
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
	assert_eq(int(_pulse.summary()["reconciled"]["places"]), 0, "nothing has been observed at all")

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
## The overlay is a READ, so this asks a question no arrival needs to answer — which is
## exactly why it is a SEPARATE seam from the reconciler. A suite that only read the epoch
## on arrival would pass while a panel asking about a place nobody is standing in got
## nothing: the ADR 0173 (c) freeze in read-only costume.
##
## Arrived FIRST, so `_stage` holds a real PLACE, and the epoch question is then asked
## about that place rather than about `""`. A stage with no place and a place nobody has
## visited must not be the same reading, which is why `place_state` reads `_location_id`.
func test_the_epoch_reader_answers_about_the_place_the_stage_is_standing_in() -> void:
	_arrive(ARRIVAL)
	# The world the stage stands in is RETIRED and its successor carries the next epoch.
	_pulse.retire_world(ARRIVAL, &"rebuilt_realm")

	var state := (
		_stage
		. place_state(
			[
				{"id": "founded_temple", "epoch": 1, "amount": 1},
				{"id": String(TEMPLE), "epoch": WorldEpoch.FIRST, "amount": 2},
			]
		)
	)

	assert_eq(
		int(state.get("epoch", 0)),
		WorldEpoch.FIRST,
		"the retired world still resolves at the epoch it lived — retirement is not an advance"
	)
	assert_eq(bool(state.get("retired", false)), true, "and reads as retired")
	assert_eq(
		(state.get("applied", []) as Array).size(),
		2,
		"and both of the epoch-1 occurrences applied, so a reader is told what it took"
	)
	# And the NEXT epoch's history is DEFERRED rather than counted, which is the overlay's
	# whole job: the successor's founding has not happened in a history this world ended.
	var successor := WorldEpoch.state_of(
		_pulse.summary()["epochs"] as Dictionary,
		&"rebuilt_realm",
		[{"id": "founded_temple", "epoch": 2, "amount": 1}]
	)
	assert_eq(
		int(successor.get("epoch", 0)),
		WorldEpoch.FIRST + 1,
		"the successor reads at the next epoch, through the same production epoch set"
	)
	assert_eq(
		int((successor.get("counts", {}) as Dictionary).get("founded_temple", 0)),
		1,
		"so its own founding counts exactly once rather than being double-counted"
	)


## ## A retired world reads its OWN history and a successor reads the newer one, with
## nothing un-recorded. That is the whole of ADR 0170's epoch, and it is asserted on the
## ledger AFTER the read, so the overlay cannot pass by withdrawing a fact.
func test_a_retired_worlds_history_is_rewritten_without_un_recording_anything() -> void:
	_arrive(ARRIVAL)
	# The ledger records BOTH histories on the one monotone row, BEFORE anything is read.
	WorldFact.record(_actor, &"lower_realm_founded", 1)
	WorldFact.record(_actor, &"rebuilt_realm_founded", 1)
	_pulse.retire_world(ARRIVAL, &"rebuilt_realm")
	var occurrences := [
		{"id": "lower_realm_founded", "epoch": WorldEpoch.FIRST, "amount": 1},
		{"id": "rebuilt_realm_founded", "epoch": 2, "amount": 1},
	]

	# The RETIRED world — the one the stage is standing in.
	var retired := _stage.place_state(occurrences)
	assert_eq(bool(retired.get("retired", false)), true, "the rebuilt world reads as retired")
	assert_eq(
		int((retired.get("counts", {}) as Dictionary).get("lower_realm_founded", 0)),
		1,
		"and sees the founding that happened during the epoch it lived"
	)
	assert_eq(
		retired.get("deferred", []) as Array,
		["rebuilt_realm_founded"],
		(
			"while NAMING the later occurrence as not-yet, so a reader can tell it from "
			+ "one that never existed"
		)
	)
	# THE MONOTONE HALF, asserted on the ledger itself rather than on the overlay.
	assert_eq(
		WorldFact.count(_actor, &"lower_realm_founded"),
		1,
		"the retired world's founding is still recorded"
	)
	assert_eq(WorldFact.count(_actor, &"rebuilt_realm_founded"), 1, "and so is the successor's")
	assert_eq(
		WorldFact.count(_actor, &"lower_realm_founded") > 0,
		true,
		"nothing was un-recorded by the rebuild (ADR 0113)"
	)


## The epoch overlay's floor is a constant of `core`, not a guess, and an unrebuilt world
## must answer epoch one rather than a refusal: "this world was never rebuilt" and
## "nothing can answer" must not be the same reading, because a panel reading the first
## as the second hides a wiring gap behind a plausible date.
##
## Arrived FIRST, so the answer is about a real place — `place_state` reads the stage's
## own `_location_id`, and a stage that never arrived would be asserting its floor about
## the empty string, which is a claim about nothing.
func test_the_stage_answers_the_first_epoch_for_a_world_nobody_rebuilt() -> void:
	_arrive(ARRIVAL)
	assert_eq(
		_stage.place_epoch(),
		WorldEpoch.FIRST,
		"a world nobody rebuilt reads as epoch one (ADR 0170)"
	)
	assert_eq(
		int(_stage.summary()["epoch"]),
		WorldEpoch.FIRST,
		"and the same figure reaches the summary as a primitive, so a panel can print it"
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
	assert_eq(bool(arrival.get("ok", false)), true, "the arrival still succeeded without the seam")
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
## guard reading these files cannot fire on their own prose.
##
## **The STRING-LITERAL-SAFE form of `test_time_ladder_single_source.gd:525`.** The
## simple form cuts a line at its first `#`, which is sound when no line it reads carries
## a string — and two assertions below look for `Callable(_world, "observe_place")`, whose
## line does. The full form is correct by construction rather than by luck, and it is
## already in the repo.
func _code_only(source: String) -> String:
	var kept: Array[String] = []
	var in_block := false
	for raw in source.split("\n"):
		var line := String(raw)
		if not in_block and line.strip_edges().begins_with("#"):
			continue
		var out := ""
		var at := 0
		var quote := ""
		while at < line.length():
			var character := line[at]
			if in_block:
				if line.substr(at, 3) == '"""':
					in_block = false
					at += 3
				else:
					at += 1
				continue
			if quote == "" and line.substr(at, 3) == '"""':
				in_block = true
				at += 3
				continue
			if quote == "" and (character == '"' or character == "'"):
				quote = character
				out += character
				at += 1
				continue
			if quote != "":
				if character == "\\":
					out += character
					at += 1
					if at < line.length():
						out += line[at]
						at += 1
					continue
				if character == quote:
					quote = ""
				out += character
				at += 1
				continue
			if character == "#":
				break
			out += character
			at += 1
		kept.append(out)
	return "\n".join(kept)
