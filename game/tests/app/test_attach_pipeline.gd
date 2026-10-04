extends TestCase

## W5: the attach pipeline's own contract — declared order, hook-before and
## hook-after semantics, the empty-stub tolerance, and the loud unknown-phase
## refusal.
##
## The loud refusal is asserted from SOURCE, not by driving it: `TestCase`
## shadows `push_error` and latches `_test_errors` (`tests/framework.gd:196`),
## so a case that triggered the refusal would go red for being correct. That
## is the same reason `tests/core/test_reconcile_stamp.gd:395` counts
## `push_error(` in source instead of calling the refusing branch.
##
## Boot equivalence — the composition root's fresh build running through the
## pipeline and attaching the same module set as the old hardcoded list — is
## asserted once the root is wired to the pipeline. This file proves the
## pipeline itself is correct; the root's wiring is a separate change.

const PIPELINE_SRC := "res://src/app/attach_pipeline.gd"


func test_phases_run_in_declared_order() -> void:
	var seen: Array = []
	var pipeline := AttachPipeline.new()
	pipeline.add_phase("first", func(_actor): seen.append("first"))
	pipeline.add_phase("second", func(_actor): seen.append("second"))
	pipeline.add_phase("third", func(_actor): seen.append("third"))
	pipeline.run(null)
	assert_eq(seen, ["first", "second", "third"], "phases run in declared order")


func test_default_hook_runs_after_its_phase() -> void:
	var seen: Array = []
	var pipeline := AttachPipeline.new()
	pipeline.add_phase("p1", func(_actor): seen.append("phase"))
	pipeline.add_hook("p1", func(_actor): seen.append("hook"))
	pipeline.run(null)
	assert_eq(seen, ["phase", "hook"], "default hook runs after its phase")


func test_before_hook_runs_before_its_phase() -> void:
	var seen: Array = []
	var pipeline := AttachPipeline.new()
	pipeline.add_phase("p1", func(_actor): seen.append("phase"))
	pipeline.add_hook("p1", func(_actor): seen.append("hook"), true)
	pipeline.run(null)
	assert_eq(seen, ["hook", "phase"], "before-hook runs before its phase")


func test_hooks_on_one_phase_fire_in_registration_order() -> void:
	var seen: Array = []
	var pipeline := AttachPipeline.new()
	pipeline.add_phase("p1", func(_actor): seen.append("phase"))
	pipeline.add_hook("p1", func(_actor): seen.append("a"))
	pipeline.add_hook("p1", func(_actor): seen.append("b"))
	pipeline.add_hook("p1", func(_actor): seen.append("c"), true)
	pipeline.run(null)
	assert_eq(seen, ["c", "phase", "a", "b"], "before-hooks, the phase, then after-hooks in order")


func test_empty_stub_hook_is_skipped_not_an_error() -> void:
	var seen: Array = []
	var pipeline := AttachPipeline.new()
	pipeline.add_phase("p1", func(_actor): seen.append("phase"))
	# W2 stakes an empty Callable() per manifest hook; it must not break a boot.
	pipeline.add_hook("p1", Callable())
	pipeline.run(null)
	assert_eq(seen, ["phase"], "an empty stub hook is skipped and the phase still runs")


func test_unknown_phase_is_a_named_loud_error() -> void:
	# Asserted from source: driving the refusal would latch TestCase's error
	# stream and fail the suite for being correct (see the file's docblock).
	var code := FileAccess.get_file_as_string(PIPELINE_SRC)
	assert_ne(code, "", "the pipeline source is readable")
	assert_eq(code.count("push_error("), 1, "exactly one loud refusal: the unknown phase")
	assert_eq(code.contains("no phase named"), true, "and it names the missing phase")
