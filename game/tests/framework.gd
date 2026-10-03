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


func _record(label: String, expected, actual) -> void:
	_failed += 1
	_failures.append("%s: expected %s, got %s" % [label, expected, actual])
	# Repetition is the signature of a loop, not of a genuinely broken assertion:
	# the same few failures repeating means the test is re-running its body. Stop
	# the process instead of writing one log line per iteration.
	if _failed >= MAX_FAILURES:
		_blow_up("%d failures in one test — the body is looping over the same failures" % _failed)
