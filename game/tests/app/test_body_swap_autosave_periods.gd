extends TestCase

## A BODY SWAP must not swallow periods from the autosave schedule (ADR 0179).
##
## ## The defect this file exists for
##
## `ItemWorkbenchPlay._periods_seen` held the world fold's running total as of the last
## `advance_world`, and `_advanced_by` answered `maxi(0, total - _periods_seen)` — which
## the docstring called "correct", because "a report whose total did not RISE moved
## nothing". That reasoning is sound WITHIN ONE FOLD and wrong ACROSS a body swap:
## `adopt_actor` builds a fresh `WorldPulse` whose total restarts at **0**, so a
## `_periods_seen` left holding the fallen body's total made every subsequent advance read
## `maxi(0, small - large)` = **0**.
##
## **The autosave therefore under-counts for up to `AUTOSAVE_PERIODS` world-moving periods
## after every rebirth, and nothing anywhere reports it.** A player who died and came back
## could lose that many periods off their save schedule with no error and no visible sign —
## the world moved, the ledger knows, and the save schedule was told "nothing happened".
##
## The fix is [method ItemWorkbenchPlay.adopt_world]: one door that sets the fold AND resets
## the delta with it, so a body swap cannot forget. The proofs below are behavioural — they
## read what the autosave was actually TOLD — rather than structural, because a structural
## pin would only prove someone typed the line.

## The whole periods between autosaves. Read off the module rather than restated, so a
## retune of the schedule moves this suite's expectations with it.
const SCHEDULE := SaveClock.AUTOSAVE_PERIODS

## Whole periods this file advances the world by. Deliberately LARGER than the schedule,
## so a swap that swallows `AUTOSAVE_PERIODS` periods cannot hide inside one advance.
const SPAN := 20

var _born: Array[Node] = []
var _store: SoulWorldLedger


func setup() -> void:
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	SaveApi.reset_clock()
	SaveApi.install_store("soul", _store)
	_clear_disk()


func teardown() -> void:
	# Everything this suite instantiated is freed HERE rather than at each call site: an
	# early return in a test would otherwise skip its own cleanup, and the runner shares
	# one process across every suite (AGENTS.md:50).
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	_clear_disk()
	_store = null
	SoulApi.set_store(null)
	SaveApi.install_store("soul", null)


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


# --- The proofs --------------------------------------------------------------


## **THE REGRESSION.** One span, then a body swap, then the SAME span again. The autosave
## must fire on BOTH, because the world moved the same number of periods both times.
##
## Before the fix the second span reported `maxi(0, SPAN - SPAN) = 0`: the schedule was
## handed "nothing moved" for a world that had just moved a full span, so it never reached
## its boundary and no save landed. Restore the old `adopt_actor` line
## (`_world = WorldPulse.new(...)` with no reset) and this goes red.
func test_a_body_swap_does_not_swallow_the_periods_the_world_just_moved() -> void:
	var root := _play()
	_attach_world(root, _actor(&"first_body"))

	var saves_before := SaveApi.clock.saves()
	root.call("advance_world", SPAN)
	assert_eq(
		SaveApi.clock.saves() - saves_before,
		1,
		"the first span reached a boundary and wrote a save"
	)

	# The rebirth: a NEW body and a NEW fold, exactly as `adopt_actor` builds them.
	root.call("adopt_actor", _actor(&"reborn_body"))

	root.call("advance_world", SPAN)
	assert_eq(
		SaveApi.clock.saves() - saves_before,
		2,
		(
			(
				"the span after a rebirth reached a boundary too: a fresh WorldPulse restarts "
				+ "its total at zero, so a `_periods_seen` left on the fallen body's total makes "
				+ "`maxi(0, %d - %d)` answer zero and the schedule never lands"
			)
			% [SPAN, SPAN]
		)
	)


## **The whole `AUTOSAVE_PERIODS` window, which is the size of the drift.** The first case
## advances past the boundary so a save fires either way; this one advances by LESS than a
## full schedule on each side of the swap, so a swallowed window leaves the clock short and
## the boundary unreached.
func test_a_swap_does_not_cost_up_to_a_whole_autosave_window() -> void:
	var half := maxi(1, SCHEDULE / 2)
	var root := _play()
	_attach_world(root, _actor(&"first_body"))

	root.call("advance_world", half)
	root.call("adopt_actor", _actor(&"reborn_body"))
	var saved := root.call("advance_world", half) as Dictionary

	assert_eq(bool(saved.get("ok", true)), true, "the post-swap advance is accepted")
	assert_eq(
		SaveApi.exists(),
		true,
		(
			(
				"%d periods before the swap plus %d after is a whole %d-period schedule, so a "
				+ "save landed: swallowing the post-swap half would leave the clock short of it"
			)
			% [half, half, SCHEDULE]
		)
	)


## And the boundary lands on the SCHEDULE-th period across the swap, not one late or never.
## This is the pairing the first case leaves implicit: the number the world reports moving
## is the number the schedule counts, and a swap that zeroes the delta breaks both at once.
func test_the_boundary_lands_on_the_schedule_period_across_a_swap() -> void:
	var root := _play()
	_attach_world(root, _actor(&"first_body"))
	root.call("advance_world", SCHEDULE - 1)
	assert_eq(SaveApi.exists(), false, "one period short of the boundary, nothing written yet")

	root.call("adopt_actor", _actor(&"reborn_body"))
	root.call("advance_world", 1)

	assert_eq(
		SaveApi.exists(),
		true,
		(
			(
				"the %dth period crossed the boundary: %d had moved before the swap and this one "
				+ "is the last"
			)
			% [SCHEDULE, SCHEDULE - 1]
		)
	)


## A swap that is never followed by an advance costs nothing and changes nothing: this is
## the shape `adopt_actor` is actually called in, and it must not write a save by itself.
func test_a_body_swap_on_its_own_moves_no_periods_and_writes_no_save() -> void:
	var root := _play()
	_attach_world(root, _actor(&"first_body"))
	root.call("advance_world", 1)
	_clear_disk()

	root.call("adopt_actor", _actor(&"reborn_body"))

	assert_eq(SaveApi.exists(), false, "a rebirth is not a period, so no save lands")
	assert_eq(
		int((root.call("world_summary") as Dictionary).get("periods", -1)),
		0,
		"and the new fold's own total really did restart at zero — the premise of the defect"
	)


# --- Structural pin ----------------------------------------------------------


## One door, so a future body swap cannot bypass the reset.
##
## `adopt_actor` assigns `_world` directly in three places historically — `_ready` and the
## swap itself — and each is a chance to forget the `_periods_seen` reset. Reading the
## source pins that the swap goes through [method ItemWorkbenchPlay.adopt_world], which is
## what makes the reset impossible to omit at that call site.
##
## Asserted structurally because the alternative is a count of a private field, and the
## behavioural cases above already cover what the reset DOES.
func test_the_body_swap_adopts_the_fold_through_the_door_that_resets_the_delta() -> void:
	var code := _code_only(FileAccess.get_file_as_string("res://src/app/item_workbench_app.gd"))
	assert_eq(code.contains("adopt_world(WorldPulse.new("), true, "the swap adopts the fold")
	assert_eq(
		code.contains("_world = WorldPulse.new(body"),
		false,
		"and never assigns it directly, which is how the reset was being skipped"
	)
	var play := FileAccess.get_file_as_string("res://src/app/item_workbench_play.gd")
	assert_eq(
		play.contains("_periods_seen = 0"),
		true,
		"and the door resets the delta it owns, in the same breath it takes the fold"
	)


# --- Fixtures ----------------------------------------------------------------


## A bare `ItemWorkbenchPlay` with no screen stack and no modules. The autosave delta is
## this half's own arithmetic and needs none of the shell's wiring, so mounting the whole
## composition root here would only add another way for an unrelated break to black this
## file out.
func _play() -> ItemWorkbenchPlay:
	var root := ItemWorkbenchPlay.new()
	_born.append(root)
	return root


## Point the root at a fold over `body`, the same shape `adopt_actor` builds: the root
## under test owns the reset, so the fixture must go through it too.
func _attach_world(root: ItemWorkbenchPlay, body: Actor) -> void:
	root.call("adopt_world", WorldPulse.new(body, BeatDirector.new()))


## One `SPAN`-period advance on the root under test.
##
## Nothing is read back out of a private field: the observable is what the SCHEDULE did —
## a save landing on disk and the clock counting one more save — because that is the thing
## the defect corrupted. Reading `_periods_seen` would re-derive the arithmetic under test.
func _advance(root: ItemWorkbenchPlay, periods: int) -> Dictionary:
	return root.call("advance_world", periods) as Dictionary


## An actor the save module can actually write: the composition root attaches `SoulApi`,
## `DifficultyApi` and the save's own store, and `poll_save` reads the difficulty id.
func _actor(id: StringName) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SoulApi.attach(actor)
	DifficultyApi.attach(actor)
	return actor


## The source with whole-line `##` comments dropped, so a guard reads CODE and is not
## fired by the prose beside it. The same substitution `test_realm_rate.gd` makes.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		kept.append(stripped)
	return "\n".join(kept)
