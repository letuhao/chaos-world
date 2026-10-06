extends TestCase

## Tests for the def injection seam (ninth seam).
##
## A mod declares def patches in its manifest's `def_patches` field. Each patch
## modifies an existing def without replacing it entirely. Operations: set, add,
## remove, multiply, add_number.

const MOD_FIXTURE := "user://w9_defpatch_mods_%d"

var _root: String = ""


func setup() -> void:
	_root = MOD_FIXTURE % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	_remove_tree(_root, 0)
	_root = ""


func _remove_tree(path: String, depth: int) -> void:
	if depth > 16 or not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var names: Array[String] = []
	var guard := 0
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


func _write_mod(dir_name: String, mod_id: String, patches: Array) -> String:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var manifest := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(
		JSON.stringify(
			{
				"id": mod_id,
				"version": "1.0",
				"priority": 0,
				"requires_api": 1,
				"def_patches": patches,
			}
		)
	)
	manifest.close()
	return dir_path


func test_def_patches_are_recorded() -> void:
	_write_mod(
		"patches",
		"w9_patches",
		[
			{"family": "items", "id": "iron_sword", "field": "value", "value": 100, "operation": "set"},
		]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "loader happy")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.def_patches.size(), 1, "patch recorded")
	assert_eq(String(ctx.def_patches[0]["family"]), "items", "family")
	assert_eq(String(ctx.def_patches[0]["id"]), "iron_sword", "id")
	assert_eq(String(ctx.def_patches[0]["field"]), "value", "field")


func test_def_patches_reach_runtime_registrations() -> void:
	_write_mod(
		"patches",
		"w9_patches",
		[
			{"family": "items", "id": "iron_sword", "field": "value", "value": 100, "operation": "set"},
			{"family": "items", "id": "iron_sword", "field": "tags", "value": "rare", "operation": "add"},
		]
	)
	var out := ModsApi.load_order([_root])
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	var patches: Array = registrations["def_patches"]
	assert_eq(patches.size(), 2, "patches reached runtime registrations")
	assert_eq(String(patches[0]["family"]), "items", "family")
	assert_eq(String(patches[0]["mod_id"]), "w9_patches", "mod id stamped")


func test_def_patch_set_operation() -> void:
	var def := Resource.new()
	def.set("value", 10)
	var patch := {"field": "value", "value": 100, "operation": "set"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], true, "set succeeded")
	assert_eq(def.get("value"), 100, "value replaced")


func test_def_patch_add_operation() -> void:
	var def := Resource.new()
	def.set("tags", ["common"])
	var patch := {"field": "tags", "value": "rare", "operation": "add"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], true, "add succeeded")
	var tags: Array = def.get("tags")
	assert_eq(tags.size(), 2, "tag appended")
	assert_eq(tags[1], "rare", "new tag present")


func test_def_patch_remove_operation() -> void:
	var def := Resource.new()
	def.set("tags", ["common", "rare"])
	var patch := {"field": "tags", "value": "common", "operation": "remove"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], true, "remove succeeded")
	var tags: Array = def.get("tags")
	assert_eq(tags.size(), 1, "tag removed")
	assert_eq(tags[0], "rare", "correct tag remains")


func test_def_patch_multiply_operation() -> void:
	var def := Resource.new()
	def.set("value", 10.0)
	var patch := {"field": "value", "value": 1.5, "operation": "multiply"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], true, "multiply succeeded")
	assert_eq(def.get("value"), 15.0, "value multiplied")


func test_def_patch_add_number_operation() -> void:
	var def := Resource.new()
	def.set("value", 10.0)
	var patch := {"field": "value", "value": 5.0, "operation": "add_number"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], true, "add_number succeeded")
	assert_eq(def.get("value"), 15.0, "value increased")


func test_def_patch_unknown_field_refused() -> void:
	var def := Resource.new()
	def.set("value", 10)
	var patch := {"field": "nonexistent", "value": 100, "operation": "set"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], false, "unknown field refused")
	assert_eq(result["reason"], "unknown_field", "named reason")


func test_def_patch_multiply_non_number_refused() -> void:
	var def := Resource.new()
	def.set("name", "sword")
	var patch := {"field": "name", "value": 2.0, "operation": "multiply"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], false, "non-number refused")
	assert_eq(result["reason"], "not_number", "named reason")


func test_def_patch_add_non_array_refused() -> void:
	var def := Resource.new()
	def.set("value", 10)
	var patch := {"field": "value", "value": 5, "operation": "add"}
	var result := DefPatch.apply(def, patch)
	assert_eq(result["ok"], false, "non-array refused")
	assert_eq(result["reason"], "not_array", "named reason")


func test_unknown_def_patch_operation_refused() -> void:
	var dir_path := _write_mod(
		"patches",
		"w9_patches",
		[{"family": "items", "id": "iron_sword", "field": "value", "value": 100, "operation": "unknown_op"}]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], false, "unknown operation refused")
	assert_eq(out["reason"], "bad_manifest", "named reason")


func test_def_patch_missing_required_fields_refused() -> void:
	var dir_path := _write_mod(
		"patches",
		"w9_patches",
		[{"family": "items", "field": "value", "value": 100, "operation": "set"}]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], false, "missing id refused")
	assert_eq(out["reason"], "bad_manifest", "named reason")
