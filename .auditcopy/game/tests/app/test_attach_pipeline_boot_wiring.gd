extends TestCase

## W5: the composition root's ONE attach list is now an AttachPipeline (ADR 0184),
## and this file proves the ROOT's wiring, not the pipeline's mechanics.
##
## The pipeline's own contract — declared order, hook-before/after semantics,
## empty-stub tolerance, the loud unknown-phase refusal — is proven by
## `tests/app/test_attach_pipeline.gd`. What is proven here is boot equivalence:
## the pipeline the root builds declares the same 22 phases, in the same order,
## as the hardcoded list it replaced, and a manifest attach hook staked to a
## phase fires when that phase runs.
##
## The phase sequence is asserted by NAME, not by side effect: the names are the
## contract a mod stakes a hook to, so a renamed phase is a broken mod contract
## even when the attach itself still works.

## The attach steps of the old hardcoded list, as phase names, in order.
const EXPECTED_PHASES: Array[StringName] = [
	&"soul",
	&"anchor",
	&"socket",
	&"loot",
	&"difficulty",
	&"race",
	&"bloodline",
	&"elements",
	&"dual_cultivation",
	&"fertility",
	&"items",
	&"set_bonus",
	&"techniques",
	&"social",
	&"destiny",
	&"event",
	&"quest",
	&"npc",
	&"domain",
	&"combat",
	&"technique_seams",
	&"economy",
]

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _saved_registrations: Dictionary = {}


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	# The manifest seam is process-wide and the runner shares one process across
	# every suite, so the boot's registrations are saved around the test that
	# stakes its own hook and restored in teardown.
	_saved_registrations = ModBoot.active_registrations.duplicate(true)


func teardown() -> void:
	ModBoot.active_registrations = _saved_registrations
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- The phase sequence ------------------------------------------------------


func test_the_root_pipeline_declares_the_legacy_attach_sequence() -> void:
	var pipeline: AttachPipeline = _app.call("_attach_pipeline")
	assert_eq(
		pipeline.phase_names(),
		EXPECTED_PHASES,
		"the pipeline's phases are the old hardcoded list's steps, in order"
	)


# --- A hook staked to a phase fires with it ---------------------------------


func test_a_hook_staked_to_a_phase_fires_when_that_phase_runs() -> void:
	var pipeline: AttachPipeline = _app.call("_attach_pipeline")
	var fired: Array = []
	pipeline.add_hook(&"items", func(_actor): fired.append("items"))
	# The full run is the point: this is the boot equivalence the old hardcoded
	# list used to provide, so every phase's real attach executes here.
	pipeline.run(_fresh_actor())
	assert_eq(fired, ["items"], "the hook fired when its phase ran")


# --- The manifest seam ------------------------------------------------------


func test_a_manifest_hook_from_the_boot_registrations_fires_through_the_root() -> void:
	var fired: Array = []
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["attach_hooks"] = [
		{"phase": "quest", "hook": func(actor): fired.append(actor.id)},
	]
	ModBoot.active_registrations = registrations
	var actor := _fresh_actor()
	_app.call("_attach_body_modules", actor)
	assert_eq(fired, [actor.id], "the manifest hook fired with the actor when its phase ran")


# --- Plumbing ----------------------------------------------------------------


## A fresh hero with the three cultivation enrolments `_build_actor` performs,
## so the pipeline's element phase has paths to read. The actor is a RefCounted
## the test's own locals release; nothing on the attach list keeps it.
func _fresh_actor() -> Actor:
	var actor := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor
