class_name TestCase
extends RefCounted

## Minimal assertion base for the headless runner. Do not use bare assert() —
## failures must be counted so the runner can exit non-zero.

## A test that fails this many times has stopped testing and started looping:
## the extra assertions only multiply the error output. Records are kept so the
## diagnosis survives, then the process is killed hard — see `_blow_up`.
const MAX_FAILURES := 200
## Same idea for passes. An unbounded `while` whose exit condition can never be
## met records a pass forever while making no progress; this converts that from
## an infinite disk-filling hang into a loud failure.
const MAX_ASSERTIONS := 5_000_000

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _assertions: int = 0
## The declaration a suite made about the body that is running. Set by the runner
## around each `test_*` call; a suite may not have a field of this name, because
## `_test_` names are reserved for it.
var _test_floor: int = 0
## Whether this body logged anything to the error stream. A `SCRIPT ERROR` cannot
## reach here, but a `push_error` inside a test can, and that is the same event
## seen from the inside: the body reported that it could not do its job.
var _test_errors: bool = false
var _test_declared: bool = false


func _count() -> void:
	_assertions += 1
	if _assertions > MAX_ASSERTIONS:
		_blow_up("%d assertions in one test — a loop is not converging" % _assertions)


func _blow_up(reason: String) -> void:
	# Deliberately not push_error: that only adds to the log we are trying to
	# protect. A non-terminating loop is a bug in the test or the module under
	# test, and the only correct response is to stop the process now, loudly,
	# rather than let a broken build fill the user's disk. See tools/godot.py,
	# which also kills the engine if this somehow does not take.
	var report := (
		"\n=== FATAL: %s ===\nsuite: %s\nfailures so far:\n%s\n"
		% [
			reason,
			get_script().resource_path,
			"\n".join(_failures.slice(maxi(0, _failures.size() - 20)))
		]
	)
	printerr(report)
	# Bypass the engine's log sink entirely: this must reach the console.
	OS.crash(report)


func assert_eq(actual, expected, label: String) -> void:
	_count()
	if actual == expected:
		_passed += 1
	else:
		_record(label, expected, actual)


func assert_almost_eq(
	actual: float, expected: float, label: String, epsilon: float = 0.0001
) -> void:
	_count()
	if absf(actual - expected) <= epsilon:
		_passed += 1
	else:
		_record(label, expected, actual)


func assert_ne(actual, unexpected, label: String) -> void:
	_count()
	if actual != unexpected:
		_passed += 1
	else:
		_record(label, "not " + str(unexpected), actual)


## Assert that the next `at_least` assertions are not reached. See
## `expect_assertions()`.
func _test_expected() -> int:
	return _test_floor


func _test_begin() -> void:
	_test_declared = true
	_test_floor = 0
	_test_errors = false


func _test_reached() -> int:
	return _assertions


func _test_completed() -> bool:
	return not _test_errors


## ## Declare how many assertions the running body must make
##
## A GDScript runtime error aborts the function it happens in and returns to the
## caller, so a body that dies half way through returns normally to the runner and
## is indistinguishable from one that finished — every assertion after the abort
## simply never runs. The tallies are per-assertion, so such a body adds neither a
## pass nor a failure, and the suite reports the shape of a green while having
## skipped its own proof. That is not theoretical: four assertions in
## `test_nation_conflict.gd` read keys a module verb had never published, the
## bodies aborted on those lines, and `Results: 726 passed, 0 failed` was printed.
##
## ## What this measures, and what it cannot
##
## The runner calls one body at a time, so a declaration is about ONE body, and a
## declaration is per SUITE rather than per test: it is written in `setup()`, where
## the setup runs, and it is the floor every test in that suite must clear. It is
## deliberately a floor rather than an exact count, so a loop-driven body that
## varies with the content it walks still satisfies it while a body that died at
## line one does not.
##
## It is a floor and not a ceiling because **GDScript offers no way to know the
## body aborted.** `call()` returns the body's value whether it ran to the end or
## died, an aborted function cannot run its own epilogue, and the engine reports
## the abort to the error stream with no hook into it from inside the script. The
## outcome that matters — "zero script errors, honestly reported" — is enforced
## where stderr already exists, in `tools/test.py`.
##
## So a body that dies mid-way and has already asserted MORE than the floor is
## still reported green by this file; what makes it visible is that its abort
## appears as a `SCRIPT ERROR` and fails the run.
##
## A suite that declares nothing still gets the old guarantee: the runner charges
## a failure to any test that asserted nothing at all.
func expect_assertions(at_least: int) -> void:
	_test_floor = maxi(0, at_least)


func setup() -> void:
	pass


## Symmetric half of `setup`. The runner calls this after EVERY test, so the
## default must exist: without it the first suite that does not override it
## aborts the whole process and the run prints no `Results:` line at all. A
## suite that needs real cleanup overrides it.
func teardown() -> void:
	pass


func passed() -> int:
	return _passed


func failed() -> int:
	return _failed


func failures() -> Array[String]:
	return _failures


## Every assertion this suite has recorded, passed or failed alike.
##
## The runner reads this immediately before and after each test method, because
## a test that asserts nothing is not a passing test -- it is a test that never
## ran. Nothing else in this file can tell those two cases apart: the tallies
## are per-assertion, so a body that returns early adds neither a pass nor a
## failure and is invisible to `passed()`/`failed()`.
func assertion_count() -> int:
	return _assertions


## Whether the framework hooks this runner needs are present. A suite that extends
## a DIFFERENT base — or a script whose `extends` failed to resolve, so the class
## fell back to something with no hooks in it — does not have them, and calling a
## hook it does not have prints a script error per call rather than saying so once.
## The runner asks this first, and charges the suite a single failure.
func _test_methods_known() -> bool:
	return true


## Whether this body logged to the error stream while it ran. GDScript has no
## overridable hook for `push_error`, so this file SHADOWS it: `push_error` is a
## global, and a script that declares a method of the same name is what every
## unqualified call in that script resolves to. The test body therefore calls this
## override, the latch sees the message, and the message is still written to
## stderr by `printerr` — a *different* global, which is why this one is the
## function that is shadowed and `printerr` is the function that survives.
##
## GDScript 4 has no way to reach the original through a qualified name: both
## `@GDScript` and `@GlobalScope` are parse errors on a global *function*, so an
## override has to re-emit through another writer. The two are indistinguishable to
## everything that matters here — both go to the same stream, and neither is a
## `SCRIPT ERROR`, which is the prefix `tools/test.py` counts.
func push_error(message: String) -> void:
	if _test_declared:
		_test_errors = true
	printerr(message)


func _record(label: String, expected, actual) -> void:
	_failed += 1
	_failures.append("%s: expected %s, got %s" % [label, expected, actual])
	# Repetition is the signature of a loop, not of a genuinely broken assertion:
	# the same few failures repeating means the test is re-running its body. Stop
	# the process instead of writing one log line per iteration.
	if _failed >= MAX_FAILURES:
		_blow_up("%d failures in one test — the body is looping over the same failures" % _failed)
