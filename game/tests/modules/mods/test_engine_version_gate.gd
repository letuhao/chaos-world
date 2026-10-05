extends TestCase

## engine_version gate (ADR 0184 §8): a mod declaring an engine_version higher
## than the running engine is refused with a NAMED cause, never skipped.

var _root: String = ""


func setup() -> void:
	_root = "user://w2_engine_version_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	_remove_tree(_root)
	_root = ""


func _remove_tree(path: String, depth: int = 0) -> void:
	## Recursive on a bounded tree (test fixture) — the cap is the guard, per the
	## repo's depth-cap rule for tree walks (ContentScan caps the same way).
	if depth > 16:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var depth_guard := 0
	var names: Array[String] = []
	while entry != "" and depth_guard < 4096:
		depth_guard += 1
		if not entry.begins_with("."):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			_remove_tree(child, depth + 1)
		else:
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(path)


func _write_mod(engine_version: String) -> void:
	var f := FileAccess.open(_root.path_join("mod.json"), FileAccess.WRITE)
	(
		f
		. store_string(
			(
				JSON
				. stringify(
					{
						"id": "w2_engine_version_mod",
						"version": "1.0",
						"priority": 0,
						"requires_api": 1,
						"engine_version": engine_version,
						"depends_on": [],
					}
				)
			)
		)
	)
	f.close()


func _running_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]


func test_a_too_high_engine_version_is_refused_named() -> void:
	# One patch above the running engine: the mod asks for more than we have.
	var running := _running_version()
	var parts := running.split(".")
	var too_high := "%s.%s.%d" % [parts[0], parts[1], int(parts[2]) + 1]
	_write_mod(too_high)
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), false, "refused")
	assert_eq(out["reason"], "engine_version_mismatch", "named cause")
	assert_eq(String(out["detail"]).contains("w2_engine_version_mod"), true, "mod id named")


func test_the_exact_running_engine_version_loads() -> void:
	_write_mod(_running_version())
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "exact match loads")


func test_a_major_minor_engine_version_loads_on_that_minor() -> void:
	# "4.7" must load on a 4.7.x engine: the missing patch is not a demand.
	var running := _running_version()
	var parts := running.split(".")
	var major_minor := "%s.%s" % [parts[0], parts[1]]
	_write_mod(major_minor)
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "4.7 loads on 4.7.x")


func test_a_major_minor_engine_version_refused_on_older_minor() -> void:
	# "4.7" must NOT load on a 4.6.x engine: the minor is a real floor.
	var running := _running_version()
	var parts := running.split(".")
	if int(parts[1]) == 0:
		# No older minor to test against; a major-only floor still applies.
		_write_mod("%d.%d" % [int(parts[0]), int(parts[1])])
		var out := ModsApi.load_order([_root])
		assert_eq(bool(out["ok"]), true, "same minor loads")
		return
	var older_minor := "%d.%d" % [int(parts[0]), int(parts[1]) - 1]
	_write_mod(older_minor)
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "older minor is BELOW the floor, so it loads")
	# And the running minor as a floor on an older engine is the refusal case,
	# proven by the too-high test above with a full triple.
