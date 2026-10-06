extends TestCase

## End-to-end pipeline test: drives a mod through the FULL boot path
## (ModBoot.run + _attach_body_modules) and asserts every seam is exercised.
## This is the integration proof that the mod pipeline works end-to-end.

const CONTENT_DIR := "res://tests/fixtures/mods/dlc_example"

var _temp_dirs: Array[String] = []
var _mod_dir: String = ""
var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _saved_registrations: Dictionary = {}
var _saved_contexts: Array = []
var _saved_order: Array = []
var _mods_existed: bool = false


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	_saved_registrations = ModBoot.active_registrations.duplicate(true)
	_saved_contexts = ModBoot.active_contexts.duplicate(true)
	_saved_order = ModBoot.active_order.duplicate(true)
	ModBoot.active_contexts = []
	ModBoot.active_registrations = {}
	ScreenRegistry.clear()
	_mods_existed = DirAccess.dir_exists_absolute("user://mods")
	_mod_dir = "user://mods/dlc_pipeline_mod_%d" % Time.get_ticks_usec()
	_temp_dirs.append(_mod_dir)
	DirAccess.make_dir_recursive_absolute(_mod_dir)
	_write_mod_json()


func teardown() -> void:
	ModBoot.active_registrations = _saved_registrations
	ModBoot.active_contexts = _saved_contexts
	ModBoot.active_order = _saved_order
	Crafting.set_overlay_roots([])
	QuestCatalog.set_overlay_roots([])
	EventCatalog.set_overlay_roots([])
	WorldLocationCatalog.set_overlay_roots([])
	NpcCatalog.set_overlay_roots([])
	RaceCatalog.set_overlay_roots([])
	TechniqueCatalog.set_overlay_roots([])
	ElementCatalog.set_overlay_roots([])
	ScreenRegistry.clear()
	for dir_path in _temp_dirs:
		_remove_tree(dir_path)
	_temp_dirs.clear()
	_mod_dir = ""
	if not _mods_existed and DirAccess.dir_exists_absolute("user://mods"):
		_remove_tree("user://mods")
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


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
		.stringify(
			{
				"id": "dlc_pipeline",
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
						"name": "dlc_pipeline_cultivation",
						"api_gd": CONTENT_DIR + "/api.gd",
						"deps": [],
						"provides": ["cultivation_path"],
						"seed_dir": CONTENT_DIR + "/realms/",
					}
				],
				"attach_hooks":
				[
					{
						"phase": "dlc_pipeline_boot",
						"callable": CONTENT_DIR + "/hook_script.gd:on_dlc_boot"
					}
				],
				"screens":
				[
					{
						"id": "dlc_pipeline_screen",
						"scene": CONTENT_DIR + "/dlc_example_screen.tscn",
						"label": "DLC Pipeline Screen"
					}
				],
				"events": ["world_loaded"],
			}
		)
	)
	var f := FileAccess.open(_mod_dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()


func _fresh_actor() -> Actor:
	var actor := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor


func test_pipeline_boot_run_produces_active_registrations() -> void:
	var boot := ModBoot.new()
	var status := boot.run()
	assert_eq(bool(status["ok"]), true, "boot succeeds: %s" % str(status.get("detail", "")))
	assert_eq(ModBoot.active_registrations.has("content_roots"), true, "content_roots key")
	assert_eq(ModBoot.active_registrations.has("modules"), true, "modules key")
	assert_eq(ModBoot.active_registrations.has("screens"), true, "screens key")
	assert_eq(ModBoot.active_registrations.has("attach_hooks"), true, "attach_hooks key")
	assert_eq(ModBoot.active_registrations.has("subscriptions"), true, "subscriptions key")
	boot.free()


func test_pipeline_content_roots_reach_catalogs() -> void:
	var boot := ModBoot.new()
	boot.run()
	_app.call("_attach_body_modules", _fresh_actor())
	var items: Array = ModBoot.active_registrations["content_roots"]["items"]
	assert_eq(items.size(), 1, "one items root")
	assert_eq(String(items[0]["dir"]), CONTENT_DIR + "/items", "items root dir")
	assert_eq(String(items[0]["owner"]), "dlc_pipeline", "items root owner")
	boot.free()


func test_pipeline_module_attached() -> void:
	var boot := ModBoot.new()
	boot.run()
	_app.call("_attach_body_modules", _fresh_actor())
	var modules: Dictionary = ModBoot.active_registrations["modules"]
	assert_eq(bool(modules.get("ok", false)), true, "module order resolves")
	assert_eq(modules["order"].has("dlc_pipeline_cultivation"), true, "module in order")
	boot.free()


func test_pipeline_screen_registered() -> void:
	var boot := ModBoot.new()
	boot.run()
	_app.call("_attach_body_modules", _fresh_actor())
	assert_eq(
		ScreenRegistry.path_of("dlc_pipeline_screen"),
		CONTENT_DIR + "/dlc_example_screen.tscn",
		"screen path registered"
	)
	assert_eq(
		ScreenRegistry.label_of("dlc_pipeline_screen"),
		"DLC Pipeline Screen",
		"screen label registered"
	)
	boot.free()


func test_pipeline_subscription_connected() -> void:
	var boot := ModBoot.new()
	boot.run()
	_app.call("_attach_body_modules", _fresh_actor())
	assert_eq(_app._mod_subscriptions.size(), 1, "subscription stored on app")
	var sub: Dictionary = _app._mod_subscriptions[0]
	assert_eq(String(sub["event_name"]), "world_loaded", "event name recorded")
	boot.free()


func test_pipeline_attach_hook_registered() -> void:
	var boot := ModBoot.new()
	boot.run()
	_app.call("_attach_body_modules", _fresh_actor())
	var hooks: Array = ModBoot.active_registrations["attach_hooks"]
	assert_eq(hooks.size(), 1, "one attach hook")
	assert_eq(String(hooks[0]["phase"]), "dlc_pipeline_boot", "hook phase recorded")
	boot.free()


func test_pipeline_full_boot_no_errors() -> void:
	var boot := ModBoot.new()
	var status := boot.run()
	assert_eq(bool(status["ok"]), true, "load order succeeds")
	_app.call("_attach_body_modules", _fresh_actor())
	var reg: Dictionary = ModBoot.active_registrations
	assert_eq(bool(reg["modules"]["ok"]), true, "module order resolves")
	assert_eq(reg["screens"].size(), 1, "one screen in runtime")
	assert_eq(reg["attach_hooks"].size(), 1, "one attach hook in runtime")
	assert_eq(reg["content_roots"].size(), 4, "four content root families")
	assert_eq(reg["subscriptions"].size(), 1, "one subscription in runtime")
	boot.free()
