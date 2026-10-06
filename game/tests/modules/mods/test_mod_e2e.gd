extends TestCase

## Simplified end-to-end test for the mod pipeline (ADR 0184).
## Tests ModsApi.load_order + ModRuntime.finalize directly without SeamHarness.
## The DLC fixture exercises every seam: content roots, a cultivation path
## module, a screen, an event subscription, and an attach hook.

const CONTENT_DIR := "res://tests/fixtures/mods/dlc_example"

var _temp_dirs: Array[String] = []
var _mod_dir: String = ""


func setup() -> void:
	ScreenRegistry.clear()
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


func test_loader_produces_registrations() -> void:
	var out := _load_mod()
	assert_eq(bool(out["ok"]), true, "load order succeeds: %s" % str(out.get("detail", "")))
	assert_eq(out["order"], ["dlc_example"], "load order has the mod id")
	assert_eq(out["contexts"].size(), 1, "one context stamped")


func test_finalize_collects_all_seams() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(reg.has("content_roots"), true, "content_roots key present")
	assert_eq(reg.has("modules"), true, "modules key present")
	assert_eq(reg.has("screens"), true, "screens key present")
	assert_eq(reg.has("attach_hooks"), true, "attach_hooks key present")
	assert_eq(reg.has("subscriptions"), true, "subscriptions key present")
	assert_eq(reg["content_roots"].size(), 4, "four content root families")
	assert_eq(reg["screens"].size(), 1, "one screen")
	assert_eq(reg["attach_hooks"].size(), 1, "one attach hook")
	assert_eq(reg["subscriptions"].size(), 1, "one subscription")


func test_content_roots_have_correct_shape() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var items: Array = reg["content_roots"]["items"]
	var world: Array = reg["content_roots"]["world"]
	assert_eq(items.size(), 1, "one items root")
	assert_eq(items[0].has("dir"), true, "items root has dir")
	assert_eq(items[0].has("owner"), true, "items root has owner")
	assert_eq(items[0].has("id_field"), true, "items root has id_field")
	assert_eq(world.size(), 1, "one world root")
	assert_eq(String(world[0]["id_field"]), "location_id", "world root id_field is location_id")


func test_cultivation_path_validates() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var modules: Dictionary = reg["modules"]
	assert_eq(bool(modules["ok"]), true, "module order resolves")
	assert_eq(modules["order"].has("dlc_example_cultivation"), true, "cultivation module in order")


func test_screen_registers() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var screens: Array = reg["screens"]
	assert_eq(screens.size(), 1, "one screen in runtime")
	assert_eq(String(screens[0]["id"]), "dlc_example_screen", "screen id recorded")


func test_event_subscription_recorded() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var subs: Array = reg["subscriptions"]
	assert_eq(subs.size(), 1, "one subscription in runtime")
	assert_eq(String(subs[0]["event_name"]), "world_loaded", "event name recorded")


func test_attach_hook_recorded() -> void:
	var out := _load_mod()
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	var hooks: Array = reg["attach_hooks"]
	assert_eq(hooks.size(), 1, "one attach hook in runtime")
	assert_eq(String(hooks[0]["phase"]), "dlc_example_boot", "hook phase recorded")


func test_full_pipeline_no_errors() -> void:
	var out := _load_mod()
	assert_eq(bool(out["ok"]), true, "load order succeeds")
	var reg := ModRuntime.finalize(out["contexts"], out["registry"])
	assert_eq(bool(reg["modules"]["ok"]), true, "module order resolves")
	assert_eq(reg["screens"].size(), 1, "one screen in runtime")
	assert_eq(reg["attach_hooks"].size(), 1, "one attach hook in runtime")
	assert_eq(reg["content_roots"].size(), 4, "four content root families")
	assert_eq(reg["subscriptions"].size(), 1, "one subscription in runtime")
	assert_eq(self._test_errors, false, "no push_error during pipeline")
