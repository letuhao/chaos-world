extends SceneTree

## Headless test runner. Discovers res://tests/**/test_*.gd suites, runs every
## `test_*` method, and exits non-zero on any failure. See godot-gdscript-headless-testing.

const TEST_ROOT := "res://tests"
## Only run suites whose path contains this. Empty runs everything. Lets a change
## be checked without paying for the whole suite.
const ARG_SUITE := "--suite"


func _initialize() -> void:
	var suite_filter := _suite_filter()
	var total_passed := 0
	var total_failed := 0
	var ran := 0
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
		for method_name in _test_methods(suite):
			suite.call(method_name)
		total_passed += suite.passed()
		total_failed += suite.failed()
		for failure in suite.failures():
			push_error("%s :: %s" % [script_path, failure])
	print("Results: %d passed, %d failed (%d suite(s))" % [total_passed, total_failed, ran])
	quit(1 if total_failed > 0 else 0)


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
