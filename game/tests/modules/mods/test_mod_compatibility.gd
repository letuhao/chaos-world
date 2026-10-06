extends TestCase

## Compatibility checks: incompatible_with and conflicts_with manifest fields.
## At load time, the loader refuses to load a mod when an incompatible or
## conflicting mod is already present — named errors, never silent skips.

var _root: String = ""


func setup() -> void:
	_root = "user://mod_compat_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	_remove_tree(_root)
	_root = ""


func _remove_tree(path: String, depth: int = 0) -> void:
	if depth > 16:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var guard := 0
	var names: Array[String] = []
	while entry != "" and guard < 4096:
		guard += 1
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


func _write_mod(dir_name: String, text: String) -> void:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _mod_json(id: String, version: String, priority: int, extra: String = "") -> String:
	return (
		'{"id": "%s", "version": "%s", "priority": %d, "requires_api": 1%s}'
		% [id, version, priority, extra]
	)


func test_incompatible_mod_is_refused() -> void:
	_write_mod("base", _mod_json("base", "1.0", 0))
	_write_mod("broken", _mod_json("broken", "1.0", 0, ', "incompatible_with": ["base"]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), false, "load refused")
	assert_eq(out["reason"], "incompatible_mod", "named error")


func test_incompatible_mod_passes_when_target_absent() -> void:
	_write_mod("lonely", _mod_json("lonely", "1.0", 0, ', "incompatible_with": ["nonexistent"]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "load succeeds when target absent")


func test_conflicting_mod_is_refused() -> void:
	_write_mod("base", _mod_json("base", "1.0", 0))
	_write_mod("clashing", _mod_json("clashing", "1.0", 0, ', "conflicts_with": ["base"]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), false, "load refused")
	assert_eq(out["reason"], "conflicting_mod", "named error")


func test_conflicting_mod_passes_when_target_absent() -> void:
	_write_mod("lonely", _mod_json("lonely", "1.0", 0, ', "conflicts_with": ["nonexistent"]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "load succeeds when target absent")


func test_incompatible_with_manifest_field_parses() -> void:
	var text := _mod_json("demo", "1.0", 0, ', "incompatible_with": ["a", "b"]')
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	var m: Dictionary = out["manifest"]
	assert_eq(m["incompatible_with"].size(), 2, "two entries")
	assert_eq(String(m["incompatible_with"][0]), "a", "first entry")
	assert_eq(String(m["incompatible_with"][1]), "b", "second entry")


func test_conflicts_with_manifest_field_parses() -> void:
	var text := _mod_json("demo", "1.0", 0, ', "conflicts_with": ["x"]')
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	var m: Dictionary = out["manifest"]
	assert_eq(m["conflicts_with"].size(), 1, "one entry")
	assert_eq(String(m["conflicts_with"][0]), "x", "entry value")


func test_incompatible_with_defaults_to_empty() -> void:
	var text := _mod_json("demo", "1.0", 0)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	assert_eq(out["manifest"]["incompatible_with"].size(), 0, "empty by default")


func test_conflicts_with_defaults_to_empty() -> void:
	var text := _mod_json("demo", "1.0", 0)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	assert_eq(out["manifest"]["conflicts_with"].size(), 0, "empty by default")
