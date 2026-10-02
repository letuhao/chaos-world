extends SceneTree

## Focused runner: execute one suite (optionally one test method) so a crash or
## failure is attributable. Temporary verification aid, not part of the gate.
##   -s res://tests/focus_runner.gd -- <suite_path> [test_name]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("FOCUS: no suite given")
		quit(2)
		return
	var suite_path: String = args[0]
	var only := args[1] if args.size() > 1 else ""
	var script: GDScript = load(suite_path)
	if script == null or not script.can_instantiate():
		printerr("FOCUS: cannot load %s" % suite_path)
		quit(2)
		return
	var suite = script.new()
	var names: Array[String] = []
	for method in suite.get_method_list():
		var method_name: String = method.name
		if method_name.begins_with("test_") and (only == "" or method_name == only):
			names.append(method_name)
	names.sort()
	for method_name in names:
		printerr("FOCUS_BEGIN %s" % method_name)
		suite.call(method_name)
		printerr("FOCUS_END %s passed=%d failed=%d" % [method_name, suite.passed(), suite.failed()])
	for failure in suite.failures():
		printerr("FOCUS_FAIL %s" % failure)
	printerr("FOCUS: passed=%d failed=%d" % [suite.passed(), suite.failed()])
	quit(1 if suite.failed() > 0 else 0)
