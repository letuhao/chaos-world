extends TestCase

## `preview` is the UI's live read model: `BodyCultivationApi.panel_state` calls
## it on every panel refresh, so anything it does to the actor is something the
## player experiences as the screen quietly training their body.
##
## The claim it has to earn is "does not mutate". Two tests carry it, because
## neither alone is enough:
##
##   1. STATE. `to_dict()` plus the full huyệt vector, the whole meridian
##      network, the reservoir's current AND maximum, the work budget, the
##      insight floor, and the milestone ledger are compared before and after.
##   2. SIGNAL. `BodyTraining.synchronize` emits on the meridian network
##      unconditionally — `unlock_for_realm` calls `_emit_changed` whether or not
##      it added anything — and on the reservoir through `set_maximum`. On a
##      body that is already synchronized those emissions change no value at all,
##      so a state diff cannot see them and an injected `synchronize()` inside
##      `preview` would pass test 1 forever. Counting the emissions closes that.
##
## That second test is why this file exists rather than one line added to
## `test_breakthrough_attempt`.

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


## Counters, boxed. A GDScript lambda captures locals BY VALUE, so a bare
## `var n := 0` incremented inside a signal handler would still read 0 and this
## test would pass against a `preview` that synchronizes the whole body.
func _watch(actor: Actor) -> Dictionary:
	var box := {"meridian": 0, "pool": 0}
	actor.meridians.changed.connect(func() -> void: box["meridian"] += 1)
	var pool := _play.reservoir(actor)
	if pool != null:
		pool.changed.connect(func() -> void: box["pool"] += 1)
	return box


# --- State -----------------------------------------------------------------


func test_preview_leaves_a_prepared_body_byte_identical() -> void:
	var actor := _play.actor()
	assert_ne(_play.seed_for(actor), null, "the ladder names a next realm")
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	var before := _play.snapshot(actor)
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], true, "the read reports what is true")
	assert_eq(preview["target"], _play.seed_for(actor).id, "and the realm it aims at")
	var differences := _play.diff(before, _play.snapshot(actor), "actor")
	assert_eq(differences.is_empty(), true, "preview mutated: %s" % "; ".join(differences))


## The same read on a body that is NOT ready. A read model that quietly trained a
## failing body would hide the very conditions it exists to report, so the
## not-ready path is a distinct risk and gets its own snapshot.
func test_preview_leaves_an_unready_body_byte_identical() -> void:
	var actor := _play.actor()
	# One omission, so the body is blocked by exactly one gate.
	_play.prepare(actor, _play.seed_for(actor).required_meridians[0])
	var before := _play.snapshot(actor)
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], false, "the read reports what is true")
	assert_eq(preview["unmet"].size(), 1, "and names the one missing gate")
	var differences := _play.diff(before, _play.snapshot(actor), "actor")
	assert_eq(differences.is_empty(), true, "preview mutated: %s" % "; ".join(differences))


## Two reads of an unchanged body must agree, and the actor must not drift
## between them. A lazily-populated or self-invalidating read is the classic way
## a "pure" preview starts writing.
func test_repeated_previews_agree_and_the_actor_never_drifts() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var first := BodyAdvancement.preview(actor)
	var baseline := _play.snapshot(actor)
	var second := BodyAdvancement.preview(actor)
	var third := BodyAdvancement.preview(actor)
	var drift := _play.diff(first, second, "preview")
	drift.append_array(_play.diff(first, third, "preview"))
	assert_eq(drift.is_empty(), true, "repeated reads disagree: %s" % "; ".join(drift))
	var moved := _play.diff(baseline, _play.snapshot(actor), "actor")
	assert_eq(moved.is_empty(), true, "actor drifted: %s" % "; ".join(moved))


# --- Signals ---------------------------------------------------------------


## The detector a state diff cannot be. `BodyTraining.synchronize` is the one
## call `preview` must never make: it unlocks channels, tops the huyệt set up,
## resizes the reservoir, and writes the resonance rank — every one of which
## belongs to a training action the player chose, not to a read.
func test_preview_emits_no_mutation_signal_on_the_body() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var box := _watch(actor)
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], true, "the read happened")
	assert_eq(box["meridian"], 0, "preview touched the meridian network")
	assert_eq(box["pool"], 0, "preview touched the shared reservoir")


## The panel's entry point is `panel_state`, not `preview`. A read model that
## mutates through the facade is exactly the bug `ui/` cannot defend against,
## because it may only reach this module through that facade.
func test_panel_state_emits_no_mutation_signal_on_the_body() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var before := _play.snapshot(actor)
	var box := _watch(actor)
	var panel := BodyCultivationApi.panel_state(actor)
	assert_eq(panel["ready"], true, "the panel read something real")
	assert_eq(box["meridian"], 0, "panel_state touched the meridian network")
	assert_eq(box["pool"], 0, "panel_state touched the shared reservoir")
	var moved := _play.diff(before, _play.snapshot(actor), "actor")
	assert_eq(moved.is_empty(), true, "panel_state mutated: %s" % "; ".join(moved))


# --- Controls --------------------------------------------------------------


## The control that keeps the signal test honest: a real training action DOES
## emit on both, so a counter stuck at zero because it was never wired up would
## be visible here.
func test_a_real_training_action_does_emit_those_signals() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var box := _watch(actor)
	BodyTraining.cultivate(actor, BodyCultivationApi.STEPS["cultivate"])
	assert_eq(box["meridian"] > 0, true, "cultivate emits on the meridian network")
	assert_eq(box["pool"] > 0, true, "cultivate emits on the reservoir")


## And the control for the state diff: a body that genuinely changed is
## genuinely caught, and the report names the field. If this ever passes, the
## differ has stopped comparing.
func test_the_state_diff_notices_a_real_change() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var before := _play.snapshot(actor)
	BodyTraining.cultivate(actor, BodyCultivationApi.STEPS["cultivate"])
	var differences := _play.diff(before, _play.snapshot(actor), "actor")
	assert_eq(differences.is_empty(), false, "the differ is wired up")
	assert_eq(
		_play.names_differences(differences, "progress"),
		true,
		"and it names the work budget: %s" % "; ".join(differences)
	)
	assert_eq(
		_play.names_differences(differences, "payload.paths"),
		true,
		"and the serialized payload: %s" % "; ".join(differences)
	)
