extends TestCase

## Tests for the mod lifecycle hooks seam (eighth seam).
##
## A mod declares lifecycle hooks in its manifest's `lifecycle_hooks` field.
## The RegistrationContext registers them, and the game loop fires them at
## the appropriate time.

const MOD_FIXTURE := "user://w8_lifecycle_mods_%d"

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


func _write_mod(dir_name: String, mod_id: String, hooks: Array) -> String:
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
				"lifecycle_hooks": hooks,
			}
		)
	)
	manifest.close()
	return dir_path


func test_lifecycle_hooks_are_recorded() -> void:
	_write_mod(
		"hooks",
		"w8_hooks",
		[
			{"event": "on_load"},
			{"event": "on_update"},
		]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "loader happy")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.lifecycle_hooks.size(), 2, "two hooks recorded")
	assert_eq(String(ctx.lifecycle_hooks[0]["event"]), "on_load", "first hook event")
	assert_eq(String(ctx.lifecycle_hooks[1]["event"]), "on_update", "second hook event")


func test_lifecycle_hooks_reach_runtime_registrations() -> void:
	_write_mod(
		"hooks",
		"w8_hooks",
		[
			{"event": "on_load"},
			{"event": "on_save"},
		]
	)
	var out := ModsApi.load_order([_root])
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	var hooks: Array = registrations["lifecycle_hooks"]
	assert_eq(hooks.size(), 2, "hooks reached runtime registrations")
	assert_eq(String(hooks[0]["event"]), "on_load", "event name")
	assert_eq(String(hooks[0]["mod_id"]), "w8_hooks", "mod id stamped")


func test_add_lifecycle_hook_seam() -> void:
	var ctx := RegistrationContext.new("w8_manual")
	var callable := Callable()
	ctx.add_lifecycle_hook("on_load", callable)
	assert_eq(ctx.lifecycle_hooks.size(), 1, "hook recorded")
	assert_eq(String(ctx.lifecycle_hooks[0]["event"]), "on_load", "event name")


func test_unknown_lifecycle_event_refused() -> void:
	var dir_path := _write_mod(
		"hooks",
		"w8_hooks",
		[{"event": "on_unknown"}]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], false, "unknown event refused")
	assert_eq(out["reason"], "bad_manifest", "named reason")


func test_all_valid_lifecycle_events_accepted() -> void:
	_write_mod(
		"hooks",
		"w8_hooks",
		[
			{"event": "on_load"},
			{"event": "on_unload"},
			{"event": "on_enable"},
			{"event": "on_disable"},
			{"event": "on_update"},
			{"event": "on_save"},
			{"event": "on_load_save"},
		]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "all valid events accepted")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.lifecycle_hooks.size(), 7, "all seven hooks recorded")


func test_lifecycle_hooks_with_callable_spec() -> void:
	_write_mod(
		"hooks",
		"w8_hooks",
		[{"event": "on_load", "callable": "res://src/modules/mods/hook_fixture.gd:on_attach"}]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "loader happy with callable spec")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.lifecycle_hooks.size(), 1, "hook recorded")
	var callable: Callable = ctx.lifecycle_hooks[0]["callable"]
	assert_eq(callable.is_valid(), true, "callable resolved")


func test_multiple_mods_can_hook_same_event() -> void:
	_write_mod(
		"first",
		"w8_first",
		[{"event": "on_load"}]
	)
	_write_mod(
		"second",
		"w8_second",
		[{"event": "on_load"}]
	)
	var out := ModsApi.load_order([_root])
	assert_eq(out["ok"], true, "both mods load")
	var registrations := ModRuntime.finalize(out["contexts"], out["registry"])
	var hooks: Array = registrations["lifecycle_hooks"]
	assert_eq(hooks.size(), 2, "both hooks recorded")
	assert_eq(String(hooks[0]["mod_id"]), "w8_first", "first mod's hook first")
	assert_eq(String(hooks[1]["mod_id"]), "w8_second", "second mod's hook second")
