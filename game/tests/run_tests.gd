extends SceneTree

## Headless test runner. Discovers res://tests/**/test_*.gd suites, runs every
## `test_*` method, and exits non-zero on any failure. See godot-gdscript-headless-testing.

const TEST_ROOT := "res://tests"
## Only run suites whose path contains this. Empty runs everything. Lets a change
## be checked without paying for the whole suite.
const ARG_SUITE := "--suite"

## Where the running tally is mirrored after EVERY suite. A GDScript runtime error in
## one suite kills this process mid-loop, and the tally at the end of the loop is then
## never printed -- one agent's in-flight file once took out all 260 suites and left a
## run with no pass/fail count at all, which reads exactly like a run that measured
## nothing. `tools/test.py` falls back to this file when stdout has no `Results:` line,
## and labels the number as incomplete rather than presenting it as a clean result.
const TALLY_PATH := "user://test-tally.txt"


func _write_tally(total_passed: int, total_failed: int, ran: int) -> void:
	var file := FileAccess.open(TALLY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(
		"Results: %d passed, %d failed (%d suite(s))" % [total_passed, total_failed, ran]
	)
	file.close()


func _initialize() -> void:
	var suite_filter := _suite_filter()
	var total_passed := 0
	var total_failed := 0
	var ran := 0
	_write_tally(total_passed, total_failed, ran)
	for script_path in _find_tests(TEST_ROOT):
		if not suite_filter.is_empty() and not script_path.contains(suite_filter):
			continue
		var script: GDScript = load(script_path)
		if script == null or not script.can_instantiate():
			push_error("%s :: failed to load suite" % script_path)
			total_failed += 1
			continue
		var suite = script.new()
		if suite == null or not (suite is TestCase):
			push_error("%s :: failed to instantiate suite" % script_path)
			total_failed += 1
			continue
		ran += 1
		# A suite that fails to LOAD prints a SCRIPT ERROR per call and asserts
		# nothing, so every test in it would be charged a failure individually and
		# the report would be one line per method explaining the same one cause. The
		# suite is charged ONCE instead, and the skip is loud.
		if not suite.call("_test_methods_known"):
			push_error(
				"%s :: the framework hooks are missing; this file is not a TestCase" % script_path
			)
			total_failed += 1
			continue
		for method_name in _test_methods(suite):
			suite.call("setup")
			# ## Why this counts assertions at all
			#
			# "Passed" and "never ran" are the same event to a per-assertion tally: a
			# body that dies part way through records neither a pass nor a failure, so
			# the suite would report `0 failed` having skipped its own proof. That is
			# worse than a red, because a red is at least honest.
			#
			# There are two ways a body gets there, and BOTH are charged:
			#   1. it asserted nothing at all — the shape a body that returns early
			#      takes, which is the usual one when a harness failed to mount;
			#   2. it asserted fewer times than the suite DECLARED in `setup()` with
			#      `expect_assertions()` — the shape a body that died mid-way takes.
			#
			# (2) is a floor, not an exact count, because GDScript cannot tell the
			# runner that a function aborted: `call()` returns the body's value either
			# way and an aborted function runs no epilogue of its own. The complement
			# — a body that clears its floor and *still* aborted — cannot be caught
			# here at all, and is caught at stderr level by `tools/test.py`. What this
			# file guarantees is that nothing reports green while having skipped the
			# bulk of a body.
			suite.call("_test_begin")
			var asserted_before: int = suite.assertion_count()
			suite.call(method_name)
			if not _assert_ran(suite, script_path, method_name, asserted_before):
				total_failed += 1
			# `teardown` runs after EVERY test, not once per suite. A suite that
			# installs a process-wide singleton (a content catalog's `shared`) and
			# only released it at the end of the file would leak it into every suite
			# that runs later, so a shipped-content assertion would fail for reasons
			# unrelated to the content it is checking.
			suite.call("teardown")
		total_passed += suite.passed()
		total_failed += suite.failed()
		for failure in suite.failures():
			push_error("%s :: %s" % [script_path, failure])
		_write_tally(total_passed, total_failed, ran)
	print("Results: %d passed, %d failed (%d suite(s))" % [total_passed, total_failed, ran])
	quit(1 if total_failed > 0 else 0)


## Charge a failure for a test that did not do what it declared it would do, and
## report which of the two reasons it was. Three separate things can go wrong and
## all three have to be visible:
##
##   - the body asserted NOTHING. That is a body that returned early, or one whose
##     harness never mounted — it is not a passing test.
##   - the body asserted FEWER times than the suite declared in `setup()`. That is
##     a body which died part way through, because every assertion after the point
##     it died at is an assertion it never made.
##   - the body logged to the error stream. `push_error` inside a test means the
##     test reported that it could not do its job, whether or not what followed
##     happened to pass.
##
## The first two are arithmetic the suite can answer on its own. The third is a
## `SCRIPT ERROR` — which GDScript will NOT route through a script's
## `push_error` override, because a runtime error is the engine reporting, not the
## script — so it cannot be caught in this file at all and is caught in
## `tools/test.py`, where stderr is already captured. A body that dies AFTER
## clearing its floor therefore still reports green here and is failed there; see
## `expect_assertions()` for why the floor is a floor.
func _assert_ran(suite: TestCase, script_path: String, method_name: String, before: int) -> bool:
	var asserted := suite.assertion_count() - before
	var declared: int = int(suite.call("_test_expected"))
	if asserted <= 0:
		push_error("%s :: %s asserted nothing" % [script_path, method_name])
		return false
	if asserted < declared:
		push_error(
			(
				(
					"%s :: %s made %d assertion(s) of the %d it declared in setup(); it did not "
					% [script_path, method_name, asserted, declared]
				)
				+ "finish its body — a GDScript error aborts a function and the run cannot "
				+ "tell that from one that passed"
			)
		)
		return false
	if not bool(suite.call("_test_completed")):
		push_error(
			(
				(
					"%s :: %s logged to the error stream; a test that reports it could not do its "
					% script_path
					% method_name
				)
				+ "job has not passed, whatever else it asserted"
			)
		)
		return false
	return true


## Read `--suite <value>` from the arguments Godot forwards after `--`.
func _suite_filter() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(ARG_SUITE)
	if index < 0 or index + 1 >= args.size():
		return ""
	return args[index + 1]


func _test_methods(suite: RefCounted) -> Array[String]:
	var names: Array[String] = []
	for method in suite.get_method_list():
		var method_name: String = method.name
		# `_test_` belongs to the framework. These are hooks, not tests, and one of
		# them takes arguments — so letting a hook into this list would fail the call
		# and abort the whole run. A suite that declares a name in the reserved
		# prefix collides with a hook rather than quietly adding a test, which is
		# exactly the collision that must be loud.
		if method_name.begins_with("test_"):
			names.append(method_name)
	names.sort()
	return names


func _find_tests(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_find_tests(path))
			elif entry.begins_with("test_") and entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
