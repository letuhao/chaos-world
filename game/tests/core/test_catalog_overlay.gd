extends TestCase

## CatalogOverlay merge engine (ADR 0184 §5): a base-first overlay stack in
## which a later root wins only ids it DECLARED in `overrides`, an undeclared
## same-id collision is a named loud error, and a missing dir degrades to an
## empty contribution. Fixtures are minimal ItemDef .tres files written to the
## OS temp dir and removed in teardown, so the suite leaves nothing in the
## project and never depends on authored data/ content.

const SCRIPT_CLASS := "ItemDef"

var _temp_root: String = ""


func setup() -> void:
	_temp_root = OS.get_environment("TEMP").path_join("cw_catalog_overlay_test")
	_ensure_dir(_temp_root)


func teardown() -> void:
	if _temp_root != "":
		_remove_tree(_temp_root)
	_temp_root = ""


static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## One fixture def per call, shaped like an authored item .tres. Returns the
## written path, or "" when the write failed.
static func _write_def(dir_path: String, def_id: String) -> String:
	var path := dir_path.path_join(def_id + ".tres")
	var text := (
		'[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]\n' % SCRIPT_CLASS
		+ "\n"
		+ '[ext_resource type="Script" path="res://src/modules/items/item_def.gd" id="1_item"]\n'
		+ "\n"
		+ "[resource]\n"
		+ 'script = ExtResource("1_item")\n'
		+ 'id = &"%s"\n' % def_id
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


## One fixture def per call, shaped like an authored world-location .tres
## whose id field is `location_id`, not `id`. Returns the written path, or ""
## when the write failed.
static func _write_location_def(dir_path: String, location_id: String) -> String:
	var path := dir_path.path_join(location_id + ".tres")
	var text := (
		'[gd_resource type="Resource" script_class="WorldLocationDef" load_steps=2 format=3]\n'
		+ "\n"
		+ '[ext_resource type="Script" path="res://src/modules/world/world_location_def.gd" id="1_loc"]\n'
		+ "\n"
		+ "[resource]\n"
		+ 'script = ExtResource("1_loc")\n'
		+ 'location_id = &"%s"\n' % location_id
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


static func _row(dir_path: String, owner: String, declared: Array = []) -> Dictionary:
	return {"dir": dir_path, "owner": owner, "declared_overrides": declared}


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


func test_empty_stack_merges_nothing() -> void:
	var result := CatalogOverlay.merge([], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), true, "an empty stack is not an error")
	assert_eq(int(result["merged"].size()), 0, "and merges no ids")


func test_single_root_merges_its_ids_in_sorted_order() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_def(base, "zeta_item")
	_write_def(base, "alpha_item")
	_write_def(base, "mid_item")
	var result := CatalogOverlay.merge([_row(base, "base")], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), true, "one root merges")
	# ContentScan sorts the files it returns, so ids land in sorted order, not
	# write order — the determinism every catalog load depends on.
	assert_eq(
		_merged_ids(result), ["alpha_item", "mid_item", "zeta_item"], "ids merge in sorted order"
	)
	assert_eq(String(result["owners"]["alpha_item"]), "base", "the owner is recorded per id")
	assert_eq(
		String(result["paths"]["alpha_item"]),
		base.path_join("alpha_item.tres"),
		"and so is the winning path"
	)


func test_overlay_appends_new_ids_after_the_base() -> void:
	var base := _temp_root.path_join("base")
	var mod := _temp_root.path_join("mod")
	_ensure_dir(base)
	_ensure_dir(mod)
	_write_def(base, "base_item")
	_write_def(mod, "mod_item")
	var result := CatalogOverlay.merge([_row(base, "base"), _row(mod, "test_mod")], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), true, "a new id is not a collision")
	assert_eq(_merged_ids(result), ["base_item", "mod_item"], "new ids append in overlay order")
	assert_eq(String(result["owners"]["mod_item"]), "test_mod", "the later root owns its new id")


func test_declared_override_replaces_the_def_at_its_earlier_position() -> void:
	var base := _temp_root.path_join("base")
	var mod := _temp_root.path_join("mod")
	_ensure_dir(base)
	_ensure_dir(mod)
	_write_def(base, "shared_item")
	_write_def(mod, "shared_item")
	_write_def(mod, "mod_only")
	var result := (
		CatalogOverlay
		. merge(
			[_row(base, "base"), _row(mod, "test_mod", PackedStringArray(["shared_item"]))],
			SCRIPT_CLASS,
		)
	)
	assert_eq(bool(result.get("ok", false)), true, "a declared override is not an error")
	# The overridden id keeps its EARLIER position in the merged list: it was
	# first seen in the base root, so it stays at index 0 while mod_only — new
	# when the mod root is walked — appends after it.
	assert_eq(
		_merged_ids(result), ["shared_item", "mod_only"], "the overridden id keeps its position"
	)
	assert_eq(
		String(result["paths"]["shared_item"]),
		mod.path_join("shared_item.tres"),
		"but its def is the later root's"
	)
	assert_eq(String(result["owners"]["shared_item"]), "test_mod", "and the later root owns it")


func test_undeclared_collision_is_a_named_loud_error() -> void:
	var base := _temp_root.path_join("base")
	var mod := _temp_root.path_join("mod")
	_ensure_dir(base)
	_ensure_dir(mod)
	_write_def(base, "shared_item")
	_write_def(mod, "shared_item")
	var result := CatalogOverlay.merge([_row(base, "base"), _row(mod, "test_mod")], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), false, "an undeclared collision fails the merge")
	assert_eq(String(result.get("reason", "")), "undeclared_override", "with the named reason")
	var detail := String(result.get("detail", ""))
	assert_eq(detail.contains("shared_item"), true, "the detail names the id")
	assert_eq(detail.contains("test_mod"), true, "the colliding owner")
	assert_eq(detail.contains(base.path_join("shared_item.tres")), true, "the earlier path")
	assert_eq(detail.contains(mod.path_join("shared_item.tres")), true, "and the later path")


func test_the_declaration_must_come_from_the_later_root() -> void:
	var base := _temp_root.path_join("base")
	var mod := _temp_root.path_join("mod")
	_ensure_dir(base)
	_ensure_dir(mod)
	_write_def(base, "shared_item")
	_write_def(mod, "shared_item")
	# The base root declaring an id it does not even own changes nothing: the
	# declaration that counts is the colliding (later) root's.
	var result := CatalogOverlay.merge(
		[_row(base, "base", ["shared_item"]), _row(mod, "test_mod")], SCRIPT_CLASS
	)
	assert_eq(
		bool(result.get("ok", false)), false, "a base declaration does not legalise the collision"
	)


func test_a_later_declared_override_beats_an_earlier_one() -> void:
	var base := _temp_root.path_join("base")
	var mod1 := _temp_root.path_join("mod1")
	var mod2 := _temp_root.path_join("mod2")
	_ensure_dir(base)
	_ensure_dir(mod1)
	_ensure_dir(mod2)
	_write_def(base, "shared_item")
	_write_def(mod1, "shared_item")
	_write_def(mod2, "shared_item")
	var result := (
		CatalogOverlay
		. merge(
			[
				_row(base, "base"),
				_row(mod1, "mod_one", ["shared_item"]),
				_row(mod2, "mod_two", ["shared_item"]),
			],
			SCRIPT_CLASS,
		)
	)
	assert_eq(bool(result.get("ok", false)), true, "both declared, so no collision")
	assert_eq(
		String(result["paths"]["shared_item"]),
		mod2.path_join("shared_item.tres"),
		"the latest declared root wins"
	)
	assert_eq(String(result["owners"]["shared_item"]), "mod_two", "and owns the id")


func test_a_missing_dir_degrades_to_an_empty_contribution() -> void:
	var result := CatalogOverlay.merge(
		[_row("res://data/no_such_directory_anywhere", "base")], SCRIPT_CLASS
	)
	assert_eq(bool(result.get("ok", false)), true, "a missing dir is not an error")
	assert_eq(int(result["merged"].size()), 0, "it contributes nothing")


func test_a_foreign_script_class_in_a_root_is_skipped() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_def(base, "real_item")
	var foreign := base.path_join("not_an_item.tres")
	var file := FileAccess.open(foreign, FileAccess.WRITE)
	assert_eq(file == null, false, "the foreign fixture writes")
	if file == null:
		return
	file.store_string('[gd_resource type="Resource" script_class="RecipeDef"]\n')
	file.close()
	var result := CatalogOverlay.merge([_row(base, "base")], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), true, "the foreign def does not fail the merge")
	assert_eq(_merged_ids(result), ["real_item"], "and is not merged as an ItemDef")


func test_a_def_without_an_id_is_skipped() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_def(base, "real_item")
	var noid := base.path_join("no_id.tres")
	var file := FileAccess.open(noid, FileAccess.WRITE)
	assert_eq(file == null, false, "the id-less fixture writes")
	if file == null:
		return
	(
		file
		. store_string(
			(
				(
					'[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]\n'
					% SCRIPT_CLASS
				)
				+ "\n"
				+ '[ext_resource type="Script" path="res://src/modules/items/item_def.gd" id="1_item"]\n'
				+ "\n"
				+ "[resource]\n"
				+ 'script = ExtResource("1_item")\n'
				+ 'id = &""\n'
			)
		)
	)
	file.close()
	var result := CatalogOverlay.merge([_row(base, "base")], SCRIPT_CLASS)
	assert_eq(bool(result.get("ok", false)), true, "the id-less def does not fail the merge")
	assert_eq(_merged_ids(result), ["real_item"], "and contributes no id of its own")


func test_merge_is_deterministic() -> void:
	var base := _temp_root.path_join("base")
	var mod := _temp_root.path_join("mod")
	_ensure_dir(base)
	_ensure_dir(mod)
	_write_def(base, "shared_item")
	_write_def(mod, "mod_item")
	var stack := [_row(base, "base"), _row(mod, "test_mod", ["shared_item"])]
	var first := CatalogOverlay.merge(stack, SCRIPT_CLASS)
	var second := CatalogOverlay.merge(stack, SCRIPT_CLASS)
	assert_eq(first, second, "same stack, same merge")


func test_a_def_with_a_non_id_id_field_merges_when_id_field_is_passed() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_location_def(base, "forest")
	_write_location_def(base, "river")
	var result := CatalogOverlay.merge([_row(base, "base")], "WorldLocationDef", "location_id")
	assert_eq(bool(result.get("ok", false)), true, "the merge succeeds")
	assert_eq(_merged_ids(result), ["forest", "river"], "location_id values merge as ids")
	assert_eq(String(result["owners"]["forest"]), "base", "the owner is recorded per id")
	assert_eq(
		String(result["paths"]["forest"]),
		base.path_join("forest.tres"),
		"and so is the winning path"
	)


func test_a_def_with_a_non_id_id_field_is_skipped_by_default() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_location_def(base, "forest")
	var result := CatalogOverlay.merge([_row(base, "base")], "WorldLocationDef")
	assert_eq(bool(result.get("ok", false)), true, "the merge still succeeds")
	assert_eq(
		int(result["merged"].size()), 0, "a def whose id field is not 'id' contributes nothing"
	)


func test_a_row_may_declare_its_own_id_field() -> void:
	var base := _temp_root.path_join("base")
	_ensure_dir(base)
	_write_location_def(base, "forest")
	var row := _row(base, "base")
	row["id_field"] = "location_id"
	var result := CatalogOverlay.merge([row], "WorldLocationDef")
	assert_eq(bool(result.get("ok", false)), true, "the merge succeeds")
	assert_eq(_merged_ids(result), ["forest"], "the row's id_field wins over the default")
