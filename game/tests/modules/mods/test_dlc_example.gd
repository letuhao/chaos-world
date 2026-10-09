extends TestCase

## End-to-end proof that a full DLC mod works through the real loader path
## (ADR 0184). The DLC mod exercises every seam: content roots, a cultivation
## path module, a screen, an event subscription, and an attach hook.
##
## The mod.json is written to a temp dir at runtime (the pattern from
## test_attach_hook_callable.gd) so the fixture mod is not discovered by
## test_example_mods.gd, which loads every mod.json under fixtures/mods/.

const CONTENT_DIR := "res://tests/fixtures/mods/dlc_example"

var _temp_dirs: Array[String] = []
var _mod_dir: String = ""


func setup() -> void:
	ScreenRegistry.clear()
	DlcExampleHook.fired = false
	_mod_dir = "user://dlc_example_mod_%d" % Time.get_ticks_usec()
	_temp_dirs.append(_mod_dir)
	DirAccess.make_dir_recursive_absolute(_mod_dir)
	_write_mod_json()


func teardown() -> void:
	ScreenRegistry.clear()
	for dir_path in _temp_dirs:
		_remove_tree(dir_path)
	_temp_dirs.clear()
	_mod_dir = ""


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


func _write_mod_json() -> void:
	var json := (
		JSON
		. stringify(
			{
				"id": "dlc_example",
				"version": "1.0",
				"priority": 40,
				"requires_api": 1,
				"depends_on": [],
				"provides": ["content", "cultivation_path", "screens", "events"],
				"content_roots":
				[
					{"family": "items", "dir": CONTENT_DIR + "/items"},
					{"family": "world", "dir": CONTENT_DIR + "/world", "id_field": "location_id"},
					{"family": "npc", "dir": CONTENT_DIR + "/npc", "id_field": "npc_id"},
					{"family": "elements", "dir": CONTENT_DIR + "/elements"},
				],
				"modules":
				[
					{
						"name": "dlc_example_cultivation",
						"api_gd": CONTENT_DIR + "/api.gd",
						"deps": [],
						"provides": ["cultivation_path"],
						"seed_dir": CONTENT_DIR + "/realms/",
					}
				],
				"attach_hooks":
				[
					{
						"phase": "dlc_example_boot",
						"callable": CONTENT_DIR + "/hook_script.gd:on_dlc_boot"
					}
				],
				"screens":
				[
					{
						"id": "dlc_example_screen",
						"scene": CONTENT_DIR + "/dlc_example_screen.tscn",
						"label": "DLC Example Screen"
					}
				],
				"events": ["world_loaded"],
			}
		)
	)
	var f := FileAccess.open(_mod_dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()


func _load_mod() -> Dictionary:
	return ModsApi.load_order([_mod_dir])


func test_dlc_mod_loads_through_loader() -> void:
	var out := _load_mod()
	assert_eq(bool(out["ok"]), true, "DLC mod loads clean: %s" % str(out.get("detail", "")))
	assert_eq(out["order"], ["dlc_example"], "load order is correct")


func test_dlc_content_roots_appear_in_finalize() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var items: Array = reg["content_roots"]["items"]
	var world: Array = reg["content_roots"]["world"]
	var npc: Array = reg["content_roots"]["npc"]
	var elements: Array = reg["content_roots"]["elements"]
	assert_eq(items.size(), 1, "one items root")
	assert_eq(String(items[0]["dir"]), CONTENT_DIR + "/items", "items root dir")
	assert_eq(String(items[0]["owner"]), "dlc_example", "items root owner")
	assert_eq(world.size(), 1, "one world root")
	assert_eq(String(world[0]["dir"]), CONTENT_DIR + "/world", "world root dir")
	assert_eq(String(world[0]["id_field"]), "location_id", "world root id_field")
	assert_eq(npc.size(), 1, "one npc root")
	assert_eq(String(npc[0]["dir"]), CONTENT_DIR + "/npc", "npc root dir")
	assert_eq(String(npc[0]["id_field"]), "npc_id", "npc root id_field")
	assert_eq(elements.size(), 1, "one elements root")
	assert_eq(String(elements[0]["dir"]), CONTENT_DIR + "/elements", "elements root dir")


func test_dlc_cultivation_path_registers() -> void:
	var out := _load_mod()
	var order: Dictionary = (out["registry"] as ModuleRegistry).order()
	assert_eq(bool(order["ok"]), true, "registry resolves")
	assert_eq(order["order"].has("dlc_example_cultivation"), true, "cultivation module in order")


func test_dlc_screen_registers() -> void:
	var out := _load_mod()
	assert_eq(
		ScreenRegistry.path_of("dlc_example_screen"),
		CONTENT_DIR + "/dlc_example_screen.tscn",
		"screen path registered",
	)
	assert_eq(
		ScreenRegistry.label_of("dlc_example_screen"),
		"DLC Example Screen",
		"screen label registered",
	)


func test_dlc_event_subscription_recorded() -> void:
	var out := _load_mod()
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.subscriptions.size(), 1, "one subscription recorded")
	assert_eq(String(ctx.subscriptions[0]["event_name"]), "world_loaded", "event name recorded")


func test_dlc_attach_hook_recorded() -> void:
	var out := _load_mod()
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.attach_hooks.size(), 1, "one attach hook recorded")
	assert_eq(String(ctx.attach_hooks[0]["phase"]), "dlc_example_boot", "hook phase recorded")
	# The callable RESOLVES: the loader splits the spec at its LAST colon, so a
	# `res://` path (whose scheme carries its own colon) binds the real function.
	var callable: Callable = ctx.attach_hooks[0]["hook"]
	assert_eq(callable.is_valid(), true, "callable resolved")
	callable.call()
	assert_eq(DlcExampleHook.fired, true, "and it fires")


func test_dlc_full_pipeline_runs_without_errors() -> void:
	var out := _load_mod()
	assert_eq(bool(out["ok"]), true, "load order succeeds")
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(bool(reg["modules"]["ok"]), true, "module order resolves")
	assert_eq(reg["screens"].size(), 1, "one screen in runtime")
	assert_eq(reg["attach_hooks"].size(), 1, "one attach hook in runtime")
	assert_eq(reg["content_roots"].size(), 4, "four content root families")
