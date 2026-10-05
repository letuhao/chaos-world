extends TestCase

## The race catalog's overlay merge (ADR 0240): an undeclared id collision is a
## loud `undeclared_override` error, never a silent last-wins overwrite.
##
## Tests `_overlay_merge()` directly rather than driving `_ensure_loaded`, because
## the latter calls `push_error` on failure and `TestCase.push_error` latches
## `_test_errors` (`tests/framework.gd:196`) — driving the refusal would fail the
## suite for being correct. The merge result dictionary is the same contract the
## catalog acts on, so asserting it here proves the wiring without tripping the
## error latch.

const AUTHORED_RACE_ID := &"commonborn"

var _temp_dirs: Array[String] = []
var _saved_overlay_stack: Array = []


func teardown() -> void:
	RaceCatalog._overlay_stack = _saved_overlay_stack
	for dir_path in _temp_dirs:
		_remove_tree(dir_path)
	_temp_dirs.clear()


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


func _write_collision_tres(dir_path: String) -> void:
	var f := FileAccess.open(dir_path.path_join("collision.tres"), FileAccess.WRITE)
	f.store_string(
		(
			'[gd_resource type="Resource" script_class="RaceDef" load_steps=2 format=3]\n'
			+ '\n[ext_resource type="Script" path="res://src/modules/race/race_def.gd" id="1"]\n'
			+ '\n[resource]\nscript = ExtResource("1")\n'
			+ 'id = &"%s"\n' % AUTHORED_RACE_ID
		)
	)
	f.close()


func test_an_undeclared_collision_is_a_loud_error() -> void:
	_saved_overlay_stack = RaceCatalog._overlay_stack
	var temp_dir := "user://race_collision_%d" % Time.get_ticks_usec()
	_temp_dirs.append(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_write_collision_tres(temp_dir)
	# The overlay row declares no overrides, so the collision with the authored
	# `commonborn` is undeclared and must be refused loudly.
	RaceCatalog._overlay_stack = [
		{
			"dir": temp_dir,
			"owner": "collision_mod",
			"declared_overrides": [],
			"id_field": "id",
		},
	]
	var catalog := RaceCatalog.new()
	var merged := catalog._overlay_merge()
	assert_eq(bool(merged.get("ok", true)), false, "collision refused")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "named cause")
	assert_eq(
		String(merged.get("detail", "")).contains(AUTHORED_RACE_ID),
		true,
		"colliding id named in the error"
	)


func test_a_declared_override_merges_cleanly() -> void:
	_saved_overlay_stack = RaceCatalog._overlay_stack
	var temp_dir := "user://race_override_%d" % Time.get_ticks_usec()
	_temp_dirs.append(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_write_collision_tres(temp_dir)
	# The same collision, but the overlay row DECLARES the override — the merge
	# succeeds and the later def wins.
	RaceCatalog._overlay_stack = [
		{
			"dir": temp_dir,
			"owner": "override_mod",
			"declared_overrides": [AUTHORED_RACE_ID],
			"id_field": "id",
		},
	]
	var catalog := RaceCatalog.new()
	var merged := catalog._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), true, "declared override merges clean")
	assert_eq(merged["paths"].has(AUTHORED_RACE_ID), true, "overridden id present in merged paths")
	assert_eq(
		String(merged["paths"][AUTHORED_RACE_ID]).contains(temp_dir), true, "later def wins the id"
	)
