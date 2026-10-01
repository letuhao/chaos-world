extends SceneTree

## Headless test runner. Discovers res://tests/**/test_*.gd suites, runs every
## `test_*` method, and exits non-zero on any failure. See godot-gdscript-headless-testing.

const TEST_ROOT := "res://tests"


func _initialize() -> void:
	var total_passed := 0
	var total_failed := 0
	for script_path in _find_tests(TEST_ROOT):
		var script: GDScript = load(script_path)
		if script == null or not script.can_instantiate():
			push_error("%s :: failed to load suite" % script_path)
			total_failed += 1
			continue
		var suite: RefCounted = script.new()
		if not (suite is TestCase):
			continue
		for method_name in _test_methods(suite):
			suite.call(method_name)
		total_passed += suite.passed()
		total_failed += suite.failed()
		for failure in suite.failures():
			push_error("%s :: %s" % [script_path, failure])
	print("Results: %d passed, %d failed" % [total_passed, total_failed])
	quit(1 if total_failed > 0 else 0)


func _test_methods(suite: RefCounted) -> Array[String]:
	var names: Array[String] = []
	for method in suite.get_method_list():
		var method_name: String = method.name
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
