extends TestCase

## .pck mounting: a .pck file in the roots is mounted via
## ProjectSettings.load_resource_pack, and a failed mount is a named error.

var _root: String = ""


func setup() -> void:
	_root = "user://w2_mod_pck_%d" % Time.get_ticks_usec()
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


func test_a_failed_pck_mount_aborts_named() -> void:
	var f := FileAccess.open(_root.path_join("fake.pck"), FileAccess.WRITE)
	f.store_string("not a real pck")
	f.close()
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), false, "refused")
	assert_eq(out["reason"], "pck_mount_failed", "named")
	assert_eq(String(out["detail"]).contains("fake.pck"), true, "the .pck file named")


func test_no_pck_files_is_a_valid_empty_order() -> void:
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "no .pck files is not an error")
	assert_eq(out["order"].size(), 0, "empty order")
