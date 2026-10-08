extends TestCase

## Tests for the mod configuration seam (seventh seam).
##
## A mod declares config options in its manifest's `config` field. The
## RegistrationContext loads them from disk at boot, and `get_config`/`set_config`
## provide typed access with persistence.

const MOD_FIXTURE := "user://w7_config_mods_%d"

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


func _write_mod(dir_name: String, mod_id: String, config: Array) -> String:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var manifest := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	(
		manifest
		. store_string(
			(
				JSON
				. stringify(
					{
						"id": mod_id,
						"version": "1.0",
						"priority": 0,
						"requires_api": 1,
						"config": config,
					}
				)
			)
		)
	)
	manifest.close()
	return dir_path


func test_config_defaults_are_loaded_at_boot() -> void:
	_write_mod(
		"cfg",
		"w7_cfg",
		[
			{
				"key": "difficulty",
				"label": "Difficulty",
				"type": "choice",
				"default": "normal",
				"choices": ["easy", "normal", "hard"]
			},
			{
				"key": "max_enemies",
				"label": "Max Enemies",
				"type": "int",
				"default": 10,
				"min": 1,
				"max": 100
			},
			{"key": "enable_feature", "label": "Enable Feature", "type": "bool", "default": true},
		]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "loader happy")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.get_config("difficulty"), "normal", "default loaded")
	assert_eq(ctx.get_config("max_enemies"), 10, "int default")
	assert_eq(ctx.get_config("enable_feature"), true, "bool default")


func test_set_config_persists_to_disk() -> void:
	_write_mod(
		"cfg", "w7_cfg", [{"key": "name", "label": "Name", "type": "string", "default": "Player"}]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("name", "Hero")
	assert_eq(result["ok"], true, "set succeeded")
	# Reload from disk
	var out2 := ModsApi.load_order([_root])
	var ctx2: RegistrationContext = out2["contexts"][0]
	assert_eq(ctx2.get_config("name"), "Hero", "persisted to disk")


func test_set_config_validates_type() -> void:
	_write_mod(
		"cfg",
		"w7_cfg",
		[{"key": "count", "label": "Count", "type": "int", "default": 5, "min": 0, "max": 10}]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("count", "not an int")
	assert_eq(result["ok"], false, "string refused for int type")
	assert_eq(result["reason"], "not_int", "named reason")


func test_set_config_validates_range() -> void:
	_write_mod(
		"cfg",
		"w7_cfg",
		[{"key": "count", "label": "Count", "type": "int", "default": 5, "min": 0, "max": 10}]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("count", 20)
	assert_eq(result["ok"], false, "above max refused")
	assert_eq(result["reason"], "above_max", "named reason")


func test_set_config_unknown_key_refused() -> void:
	_write_mod(
		"cfg", "w7_cfg", [{"key": "name", "label": "Name", "type": "string", "default": "Player"}]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("unknown", "value")
	assert_eq(result["ok"], false, "unknown key refused")
	assert_eq(result["reason"], "unknown_key", "named reason")


func test_get_config_unknown_key_returns_null() -> void:
	_write_mod(
		"cfg", "w7_cfg", [{"key": "name", "label": "Name", "type": "string", "default": "Player"}]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.get_config("unknown"), null, "unknown key returns null")


func test_choice_type_validates_against_choices() -> void:
	_write_mod(
		"cfg",
		"w7_cfg",
		[
			{
				"key": "color",
				"label": "Color",
				"type": "choice",
				"default": "red",
				"choices": ["red", "green", "blue"]
			}
		]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("color", "yellow")
	assert_eq(result["ok"], false, "not in choices refused")
	assert_eq(result["reason"], "not_in_choices", "named reason")
	result = ctx.set_config("color", "green")
	assert_eq(result["ok"], true, "valid choice accepted")


func test_float_type_accepts_int_and_float() -> void:
	_write_mod(
		"cfg",
		"w7_cfg",
		[
			{
				"key": "multiplier",
				"label": "Multiplier",
				"type": "float",
				"default": 1.0,
				"min": 0.1,
				"max": 10.0
			}
		]
	)
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result := ctx.set_config("multiplier", 2)
	assert_eq(result["ok"], true, "int accepted for float type")
	result = ctx.set_config("multiplier", 2.5)
	assert_eq(result["ok"], true, "float accepted")


func test_config_file_is_valid_json() -> void:
	var dir_path := _write_mod(
		"cfg", "w7_cfg", [{"key": "name", "label": "Name", "type": "string", "default": "Player"}]
	)
	# Write invalid JSON to the config file
	var config_dir := dir_path.path_join("..").path_join("w7_cfg")
	var file := FileAccess.open(config_dir.path_join("config.json"), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	var out := ModsApi.load_order([_root])
	# The loader should still succeed, but config loading fails
	assert_eq(out["ok"], true, "loader succeeds even with bad config file")
	var ctx: RegistrationContext = out["contexts"][0]
	# Config values should be empty (load failed)
	assert_eq(ctx.get_config("name"), null, "config not loaded from bad file")
