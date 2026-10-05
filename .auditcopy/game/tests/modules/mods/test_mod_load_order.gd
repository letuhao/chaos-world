extends TestCase

## The loader's whole reason to exist: a deterministic order every run, and a
## NAMED cause when the graph is broken — cycle, missing dep, version
## mismatch, duplicate id — never a silent skip.

var _root: String = ""


func setup() -> void:
	_root = "user://w2_mod_loader_%d" % Time.get_ticks_usec()
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


func _write_mod(dir_name: String, text: String) -> void:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _mod(
	id: String, version: String, priority: int, deps: String = "[]", events: String = "[]"
) -> String:
	return (
		'{"id": "%s", "version": "%s", "priority": %d, "requires_api": 1, "depends_on": %s, "events": %s}'
		% [id, version, priority, deps, events]
	)


func test_dependencies_always_load_before_their_dependents() -> void:
	_write_mod("a", _mod("a", "1.0", 0))
	_write_mod("b", _mod("b", "1.0", 0, '[{"id": "a"}]'))
	_write_mod("c", _mod("c", "1.0", 0, '[{"id": "b"}]'))
	_write_mod("d", _mod("d", "1.0", 0, '[{"id": "c"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "valid graph")
	assert_eq(out["order"], ["a", "b", "c", "d"], "deps precede dependents at every depth")


func test_priority_breaks_a_same_depth_tie_higher_loads_later() -> void:
	_write_mod("low", _mod("low", "1.0", 1))
	_write_mod("high", _mod("high", "1.0", 9))
	_write_mod("mid", _mod("mid", "1.0", 5))
	var out := ModsApi.load_order([_root])
	assert_eq(out["order"], ["low", "mid", "high"], "ascending priority at depth 0")


func test_id_breaks_a_same_priority_tie_for_stability() -> void:
	_write_mod("zeta", _mod("zeta", "1.0", 5))
	_write_mod("alpha", _mod("alpha", "1.0", 5))
	_write_mod("mu", _mod("mu", "1.0", 5))
	var out := ModsApi.load_order([_root])
	assert_eq(out["order"], ["alpha", "mu", "zeta"], "ids sort the tie")


func test_the_order_is_deterministic_across_runs() -> void:
	_write_mod("a", _mod("a", "1.0", 3, '[{"id": "base"}]'))
	_write_mod("base", _mod("base", "1.0", 1))
	_write_mod("c", _mod("c", "1.0", 3))
	var first := ModsApi.load_order([_root])
	var second := ModsApi.load_order([_root])
	assert_eq(first["order"], second["order"], "same roots, same order, twice")


func test_a_cycle_aborts_and_names_every_member() -> void:
	_write_mod("a", _mod("a", "1.0", 0, '[{"id": "b"}]'))
	_write_mod("b", _mod("b", "1.0", 0, '[{"id": "c"}]'))
	_write_mod("c", _mod("c", "1.0", 0, '[{"id": "a"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), false, "refused")
	assert_eq(out["reason"], "dependency_cycle", "named")
	assert_eq(String(out["detail"]).contains("a"), true, "member a named")
	assert_eq(String(out["detail"]).contains("b"), true, "member b named")
	assert_eq(String(out["detail"]).contains("c"), true, "member c named")


func test_a_self_dependency_is_a_named_cycle() -> void:
	_write_mod("loop", _mod("loop", "1.0", 0, '[{"id": "loop"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "dependency_cycle", "self-edge names the cycle")


func test_a_missing_dep_aborts_and_names_both_ends() -> void:
	_write_mod("a", _mod("a", "1.0", 0, '[{"id": "ghost"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "missing_dependency", "named")
	assert_eq(String(out["detail"]).contains("a"), true, "requirer named")
	assert_eq(String(out["detail"]).contains("ghost"), true, "missing dep named")


func test_a_version_below_min_version_aborts_named() -> void:
	_write_mod("base", _mod("base", "1.0", 0))
	_write_mod("a", _mod("a", "1.0", 0, '[{"id": "base", "min_version": "2.0"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "version_mismatch", "named")
	assert_eq(String(out["detail"]).contains("base"), true, "dep named")
	assert_eq(String(out["detail"]).contains("2.0"), true, "floor named")


func test_a_version_at_min_version_is_accepted() -> void:
	_write_mod("base", _mod("base", "2.0", 0))
	_write_mod("a", _mod("a", "1.0", 0, '[{"id": "base", "min_version": "2.0"}]'))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "floor inclusive")


func test_a_duplicate_id_aborts_named() -> void:
	_write_mod("one", _mod("same", "1.0", 0))
	_write_mod("two", _mod("same", "2.0", 0))
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "duplicate_mod_id", "named")
	assert_eq(String(out["detail"]).contains("same"), true, "the shared id named")


func test_a_newer_requires_api_aborts_named() -> void:
	_write_mod("future", '{"id": "future", "version": "1.0", "priority": 0, "requires_api": 999}')
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "api_version_mismatch", "named")
	assert_eq(String(out["detail"]).contains("future"), true, "the mod named")


func test_an_empty_tree_is_a_valid_empty_order() -> void:
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "no mods is not an error")
	assert_eq(out["order"].size(), 0, "empty order")
	assert_eq(out["contexts"].size(), 0, "no contexts either")


func test_a_bad_manifest_aborts_with_its_path() -> void:
	_write_mod("broken", "{ not json")
	var out := ModsApi.load_order([_root])
	assert_eq(out["reason"], "bad_manifest", "named")
	assert_eq(String(out["detail"]).contains("mod.json"), true, "the path named")
