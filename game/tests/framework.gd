class_name TestCase
extends RefCounted

## Minimal assertion base for the headless runner. Do not use bare assert() —
## failures must be counted so the runner can exit non-zero.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_record(label, expected, actual)


func assert_almost_eq(
	actual: float, expected: float, label: String, epsilon: float = 0.0001
) -> void:
	if absf(actual - expected) <= epsilon:
		_passed += 1
	else:
		_record(label, expected, actual)


func assert_ne(actual, unexpected, label: String) -> void:
	if actual != unexpected:
		_passed += 1
	else:
		_record(label, "not " + str(unexpected), actual)


func passed() -> int:
	return _passed


func failed() -> int:
	return _failed


func failures() -> Array[String]:
	return _failures


func _record(label: String, expected, actual) -> void:
	_failed += 1
	_failures.append("%s: expected %s, got %s" % [label, expected, actual])
