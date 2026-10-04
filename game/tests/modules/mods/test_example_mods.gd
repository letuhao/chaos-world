extends TestCase

## End-to-end proof that the mods system works for real (ADR 0184): two fixture
## mods under game/tests/fixtures/mods/ — a data-only third-party mod and a
## first-party module mod — loaded through the same loader path, registered
## through the same seams, and merged into the same catalogs.

const FIXTURES_DIR := "res://tests/fixtures/mods"
const THIRD_PARTY_DIR := "res://tests/fixtures/mods/third_party_data"
const FIRST_PARTY_DIR := "res://tests/fixtures/mods/first_party_module"

var _temp_dirs: Array[String] = []


func setup() -> void:
	# The seams forward register_screen to the static ScreenRegistry, so each
	# test starts from an empty route table.
	ScreenRegistry.clear()


func teardown() -> void:
	ScreenRegistry.clear()
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


func _load_fixtures() -> Dictionary:
	return ModsApi.load_order([FIXTURES_DIR])


func test_load_order_loads_both_fixtures_in_priority_order() -> void:
	var out := _load_fixtures()
	assert_eq(bool(out["ok"]), true, "both fixtures load clean")
	assert_eq(out["order"], ["w8_third_party_data", "w8_first_party_module"], "priority order")


func test_contexts_are_stamped_for_both_mods() -> void:
	var out := _load_fixtures()
	assert_eq(out["contexts"].size(), 2, "one ctx per mod")
	var ctx_a := out["contexts"][0] as RegistrationContext
	var ctx_b := out["contexts"][1] as RegistrationContext
	assert_eq(ctx_a.mod_id, "w8_third_party_data", "first ctx is the data mod")
	assert_eq(ctx_b.mod_id, "w8_first_party_module", "second ctx is the module mod")


func test_data_mod_content_roots_appear_in_finalize() -> void:
	var out := _load_fixtures()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var items: Array = reg["content_roots"]["items"]
	var world: Array = reg["content_roots"]["world"]
	assert_eq(items.size(), 1, "one items root")
	assert_eq(String(items[0]["dir"]), THIRD_PARTY_DIR + "/items", "items root dir")
	assert_eq(String(items[0]["owner"]), "w8_third_party_data", "items root owner")
	assert_eq(world.size(), 1, "one world root")
	assert_eq(String(world[0]["dir"]), THIRD_PARTY_DIR + "/world", "world root dir")
	assert_eq(String(world[0]["owner"]), "w8_third_party_data", "world root owner")


func test_module_mod_registers_through_module_registry() -> void:
	var out := _load_fixtures()
	var order: Dictionary = (out["registry"] as ModuleRegistry).order()
	assert_eq(bool(order["ok"]), true, "registry resolves")
	assert_eq(order["order"].has("w8_fixture_module"), true, "fixture module in order")


func test_module_mod_registers_screen_through_screen_registry() -> void:
	var out := _load_fixtures()
	assert_eq(
		ScreenRegistry.path_of("w8_fixture_screen"),
		FIRST_PARTY_DIR + "/fixture_screen.tscn",
		"screen path registered",
	)
	assert_eq(
		ScreenRegistry.label_of("w8_fixture_screen"), "Fixture Screen", "screen label registered"
	)


func test_catalog_merge_produces_new_ids() -> void:
	var out := _load_fixtures()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var items: Array = reg["content_roots"]["items"]
	var item_merge := CatalogOverlay.merge(items, "ItemDef")
	assert_eq(bool(item_merge["ok"]), true, "items merge clean")
	assert_eq(
		item_merge["paths"].has("W8_fixture_ember_charm"), true, "new item id in merged catalog"
	)
	var world: Array = reg["content_roots"]["world"]
	# WorldLocationDef ids live in `location_id`, not `id` — the merge must be
	# told which field holds the id or every def is skipped as having no id.
	var world_merge := CatalogOverlay.merge(world, "WorldLocationDef", "location_id")
	assert_eq(bool(world_merge["ok"]), true, "world merge clean")
	assert_eq(
		world_merge["paths"].has("W8_fixture_scorched_hollow"),
		true,
		"new world id in merged catalog",
	)


func test_an_undeclared_override_collision_errors() -> void:
	# WorldLocationDef, not ItemDef: the collision proof must not depend on the
	# items script chain, so an unrelated break there cannot abort this test.
	var temp_dir := "user://w8_collision_%d" % Time.get_ticks_usec()
	_temp_dirs.append(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var f := FileAccess.open(temp_dir.path_join("collision.tres"), FileAccess.WRITE)
	(
		f
		. store_string(
			(
				'[gd_resource type="Resource" script_class="WorldLocationDef" load_steps=2 format=3]\n'
				+ '\n[ext_resource type="Script" path="res://src/modules/world/world_location_def.gd" id="1"]\n'
				+ '\n[resource]\nscript = ExtResource("1")\n'
				+ 'location_id = &"W8_fixture_scorched_hollow"\ndisplay_name = "Collision Hollow"\n'
			)
		)
	)
	f.close()
	var stack: Array[Dictionary] = [
		{
			"dir": THIRD_PARTY_DIR + "/world",
			"owner": "w8_third_party_data",
			"declared_overrides": [],
			"id_field": "location_id",
		},
		{
			"dir": temp_dir,
			"owner": "collision_mod",
			"declared_overrides": [],
			"id_field": "location_id",
		},
	]
	var out := CatalogOverlay.merge(stack, "WorldLocationDef", "location_id")
	assert_eq(bool(out["ok"]), false, "collision refused")
	assert_eq(out["reason"], "undeclared_override", "named cause")
	assert_eq(
		String(out["detail"]).contains("W8_fixture_scorched_hollow"), true, "colliding id named"
	)
