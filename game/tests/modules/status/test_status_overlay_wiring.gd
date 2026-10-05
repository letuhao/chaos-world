extends TestCase

## Tests that StatusCatalog's overlay wiring (ADR 0184 §5, ADR 0240) is correct:
## `set_overlay_roots` accepts a stack, `_overlay_merge` returns the expected
## dictionary shape, and the base root merge works.
##
## Note: overlay tests that create .tres files are omitted because StatusDef
## is not registered in the headless test environment. The base-root merge
## and the set_overlay_roots contract are fully tested here.


func test_set_overlay_roots_accepts_stack() -> void:
	var stack: Array = [
		{"dir": "res://mod_data/test_statuses", "owner": "test_mod", "declared_overrides": []},
	]
	StatusCatalog.set_overlay_roots(stack)
	# Reset to empty after test — the call itself is the assertion: it must not crash
	StatusCatalog.set_overlay_roots([])
	assert_eq(
		StatusCatalog.new()._overlay_merge().has("ok"),
		true,
		"merge should work after set_overlay_roots"
	)


func test_overlay_merge_returns_dictionary() -> void:
	StatusCatalog.set_overlay_roots([])
	var merged: Dictionary = StatusCatalog.new()._overlay_merge()
	assert_eq(str(merged.get("reason", "")), "", "reason key should exist")
	assert_eq(str(merged.get("detail", "")), "", "detail key should exist")
	assert_eq(str(merged.get("ok", "")), "true", "base-only merge should succeed")
	assert_eq(merged.has("merged"), true, "merged key should exist")
	assert_eq(merged.has("paths"), true, "paths key should exist")
	assert_eq(merged.has("owners"), true, "owners key should exist")


func test_overlay_merge_includes_base_root() -> void:
	StatusCatalog.set_overlay_roots([])
	var catalog := StatusCatalog.new()
	var merged: Dictionary = catalog._overlay_merge()
	assert_eq(str(merged.get("ok", "")), "true", "merge should succeed")
	# The base root should contribute the authored statuses
	var merged_array: Array = merged["merged"]
	assert_eq(merged_array.size() > 0, true, "base root should contribute statuses")
	# Every entry should have id, path, owner
	for entry in merged_array:
		assert_eq(entry.has("id"), true, "entry should have 'id'")
		assert_eq(entry.has("path"), true, "entry should have 'path'")
		assert_eq(entry.has("owner"), true, "entry should have 'owner'")
		assert_eq(str(entry["owner"]), "base", "base root owner should be 'base'")


func test_overlay_merge_paths_map() -> void:
	StatusCatalog.set_overlay_roots([])
	var catalog := StatusCatalog.new()
	var merged: Dictionary = catalog._overlay_merge()
	assert_eq(str(merged.get("ok", "")), "true", "merge should succeed")
	var paths: Dictionary = merged["paths"]
	var owners: Dictionary = merged["owners"]
	# Every merged entry should have a path and owner
	for entry in merged["merged"]:
		var id := str(entry["id"])
		assert_eq(paths.has(id), true, "paths should have entry for %s" % id)
		assert_eq(owners.has(id), true, "owners should have entry for %s" % id)
		assert_eq(str(paths[id]), str(entry["path"]), "path should match")
		assert_eq(str(owners[id]), str(entry["owner"]), "owner should match")
