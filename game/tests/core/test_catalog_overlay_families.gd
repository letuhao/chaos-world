extends TestCase

## Catalog overlay integration (ADR 0184 §5, ADR 0240): each non-items catalog
## routes its overlay stack through CatalogOverlay.merge, so an undeclared
## id collision is a loud error and each row's id_field is honored. Fixtures
## are minimal .tres files written to the OS temp dir and removed in teardown.

var _temp_root: String = ""


func setup() -> void:
	_temp_root = OS.get_environment("TEMP").path_join("cw_catalog_overlay_families_test")
	_ensure_dir(_temp_root)


func teardown() -> void:
	# Reset every catalog's overlay stack so no test leaks into another.
	WorldLocationCatalog.set_overlay_roots([])
	NpcCatalog.set_overlay_roots([])
	TechniqueCatalog.set_overlay_roots([])
	ElementCatalog.set_overlay_roots([])
	QuestCatalog.set_overlay_roots([])
	EventCatalog.set_overlay_roots([])
	if _temp_root != "":
		_remove_tree(_temp_root)
	_temp_root = ""


static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## One fixture def per call. `id_field` is the def property holding the id
## (e.g. "location_id" for WorldLocationDef, "npc_id" for NpcDef, "id" for
## the rest). Returns the written path, or "" when the write failed.
static func _write_def(
	dir_path: String, script_class: String, script_path: String, id_field: String, id_value: String
) -> String:
	var path := dir_path.path_join(id_value + ".tres")
	var text := (
		'[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]\n' % script_class
		+ "\n"
		+ '[ext_resource type="Script" path="%s" id="1_def"]\n' % script_path
		+ "\n"
		+ "[resource]\n"
		+ 'script = ExtResource("1_def")\n'
		+ '%s = &"%s"\n' % [id_field, id_value]
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


static func _row(
	dir_path: String, owner: String, id_field: String, declared: Array = []
) -> Dictionary:
	return {"dir": dir_path, "owner": owner, "declared_overrides": declared, "id_field": id_field}


static func _merged_ids(result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for entry in result["merged"]:
		ids.append(String(entry["id"]))
	return ids


## Flat delete of the fixture tree. Fixtures are flat by construction, so the
## recursion never passes depth one in practice; the cap names the bound that
## makes it safe regardless, and the `while` is the DirAccess terminator the
## no-unbounded-wait gate accepts.
static func _remove_tree(dir_path: String, depth: int = 0) -> void:
	if depth > 4:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(path, depth + 1)
		else:
			DirAccess.remove_absolute(path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


# --- WorldLocationCatalog ---------------------------------------------------


func test_world_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(
		mod1,
		"WorldLocationDef",
		"res://src/modules/world/world_location_def.gd",
		"location_id",
		"shared_loc"
	)
	_write_def(
		mod2,
		"WorldLocationDef",
		"res://src/modules/world/world_location_def.gd",
		"location_id",
		"shared_loc"
	)
	var stack: Array = [
		_row(mod1, "mod_one", "location_id"),
		_row(mod2, "mod_two", "location_id"),
	]
	WorldLocationCatalog.set_overlay_roots(stack)
	var merged := WorldLocationCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")
	var detail := String(merged.get("detail", ""))
	assert_eq(detail.contains("shared_loc"), true, "the detail names the id")
	assert_eq(detail.contains("mod_two"), true, "the colliding owner")


func test_world_catalog_merge_honors_id_field() -> void:
	var mod := _temp_root.path_join("mod")
	_ensure_dir(mod)
	_write_def(
		mod,
		"WorldLocationDef",
		"res://src/modules/world/world_location_def.gd",
		"location_id",
		"custom_loc"
	)
	var stack: Array = [_row(mod, "test_mod", "location_id")]
	WorldLocationCatalog.set_overlay_roots(stack)
	var merged := WorldLocationCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), true, "the merge succeeds")
	assert_eq(
		_merged_ids(merged).has("custom_loc"), true, "the location_id value is read as the id"
	)


# --- NpcCatalog -------------------------------------------------------------


func test_npc_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(mod1, "NpcDef", "res://src/modules/npc/npc_def.gd", "npc_id", "shared_npc")
	_write_def(mod2, "NpcDef", "res://src/modules/npc/npc_def.gd", "npc_id", "shared_npc")
	var stack: Array = [
		_row(mod1, "mod_one", "npc_id"),
		_row(mod2, "mod_two", "npc_id"),
	]
	NpcCatalog.set_overlay_roots(stack)
	var merged := NpcCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")


func test_npc_catalog_merge_honors_id_field() -> void:
	var mod := _temp_root.path_join("mod")
	_ensure_dir(mod)
	_write_def(mod, "NpcDef", "res://src/modules/npc/npc_def.gd", "npc_id", "custom_npc")
	var stack: Array = [_row(mod, "test_mod", "npc_id")]
	NpcCatalog.set_overlay_roots(stack)
	var merged := NpcCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), true, "the merge succeeds")
	assert_eq(_merged_ids(merged).has("custom_npc"), true, "the npc_id value is read as the id")


# --- TechniqueCatalog -------------------------------------------------------


func test_techniques_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(
		mod1, "TechniqueDef", "res://src/modules/techniques/technique_def.gd", "id", "shared_tech"
	)
	_write_def(
		mod2, "TechniqueDef", "res://src/modules/techniques/technique_def.gd", "id", "shared_tech"
	)
	var stack: Array = [
		_row(mod1, "mod_one", "id"),
		_row(mod2, "mod_two", "id"),
	]
	TechniqueCatalog.set_overlay_roots(stack)
	var merged := TechniqueCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")


# --- ElementCatalog ---------------------------------------------------------


func test_elements_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(mod1, "ElementDef", "res://src/modules/elements/element_def.gd", "id", "shared_elem")
	_write_def(mod2, "ElementDef", "res://src/modules/elements/element_def.gd", "id", "shared_elem")
	var stack: Array = [
		_row(mod1, "mod_one", "id"),
		_row(mod2, "mod_two", "id"),
	]
	ElementCatalog.set_overlay_roots(stack)
	var merged := ElementCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")


# --- QuestCatalog -----------------------------------------------------------


func test_quest_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(mod1, "QuestDef", "res://src/modules/quest/quest_def.gd", "id", "shared_quest")
	_write_def(mod2, "QuestDef", "res://src/modules/quest/quest_def.gd", "id", "shared_quest")
	var stack: Array = [
		_row(mod1, "mod_one", "id"),
		_row(mod2, "mod_two", "id"),
	]
	QuestCatalog.set_overlay_roots(stack)
	var merged := QuestCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")


# --- EventCatalog -----------------------------------------------------------


func test_event_catalog_merge_enforces_collision_policy() -> void:
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(mod1, "EventDef", "res://src/modules/event/event_def.gd", "id", "shared_event")
	_write_def(mod2, "EventDef", "res://src/modules/event/event_def.gd", "id", "shared_event")
	var stack: Array = [
		_row(mod1, "mod_one", "id"),
		_row(mod2, "mod_two", "id"),
	]
	EventCatalog.set_overlay_roots(stack)
	var merged := EventCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(merged.get("reason", "")), "undeclared_override", "with the named reason")
