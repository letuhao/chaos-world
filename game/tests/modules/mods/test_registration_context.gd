extends TestCase

## The five seams from ADR 0184 §6: stable names, stable arity, and a
## record-through-the-seams loader pass, so W3+ can swap the recording stub
## for real wiring without a signature change.

var _root: String = ""


func setup() -> void:
	# The seams forward to the static ScreenRegistry, so each test starts from an
	# empty route table — a duplicate id across tests would push_error.
	ScreenRegistry.clear()
	_root = "user://w2_mod_ctx_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	ScreenRegistry.clear()
	_remove_tree(_root)
	_root = ""


func _remove_tree(path: String, depth: int = 0) -> void:
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


func test_the_five_seams_record_and_return_their_list() -> void:
	var ctx := ModsApi.build_context("demo")
	assert_eq(ctx.add_content_root("items", "res://data/items").size(), 1, "root recorded")
	assert_eq(
		ctx.register_module("demo", "res://demo/api.gd", ["items"]).size(), 1, "module recorded"
	)
	assert_eq(ctx.add_attach_hook("economy", Callable()).size(), 1, "hook recorded")
	assert_eq(ctx.register_screen("demo", "res://demo.tscn", "Demo").size(), 1, "screen recorded")
	assert_eq(
		(
			ctx
			. subscribe(
				{"event_bus": "WorldEvents", "event_name": "period", "callable": Callable()}
			)
			. size()
		),
		1,
		"subscription recorded"
	)
	var rec := ctx.registrations()
	assert_eq(rec["mod_id"], "demo", "mod id on the record")
	assert_eq(String(rec["content_roots"]["items"][0]["dir"]), "res://data/items", "root row")
	assert_eq(String(rec["content_roots"]["items"][0]["owner"]), "demo", "root owner is the mod")
	assert_eq(String(rec["modules"][0]["api_gd"]), "res://demo/api.gd", "module row")
	assert_eq(String(rec["attach_hooks"][0]["phase"]), "economy", "hook row")
	assert_eq(String(rec["screens"][0]["label"]), "Demo", "screen row")
	assert_eq(rec["subscriptions"].size(), 1, "subscription row")


func test_the_loader_stamps_one_context_per_mod_in_order() -> void:
	var dir_path := _root.path_join("demo")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(
		(
			'{"id": "demo", "version": "1.0", "priority": 0, "requires_api": 1,'
			+ ' "content_roots": [{"family": "items", "dir": "res://x"}],'
			+ ' "modules": [{"name": "demo", "api_gd": "res://demo/api.gd"}],'
			+ ' "attach_hooks": [{"phase": "economy"}],'
			+ ' "screens": [{"id": "demo", "scene": "res://demo.tscn", "label": "Demo"}],'
			+ ' "events": ["period"]}'
		)
	)
	f.close()
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "loader happy")
	assert_eq(out["contexts"].size(), 1, "one ctx")
	var ctx := out["contexts"][0] as RegistrationContext
	assert_eq(ctx.mod_id, "demo", "ctx named by its mod")
	assert_eq(ctx.content_roots.size(), 1, "root stamped")
	assert_eq(ctx.modules.size(), 1, "module stamped")
	assert_eq(ctx.attach_hooks.size(), 1, "hook stamped (empty Callable until W3 binds it)")
	assert_eq(ctx.screens.size(), 1, "screen stamped")
	assert_eq(ctx.subscriptions.size(), 1, "subscription stamped")
	assert_eq(ctx.subscriptions[0] is Dictionary, true, "the declared events ride to the bus")


func test_an_empty_loader_pass_returns_no_contexts() -> void:
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "no mods is fine")
	assert_eq(out["contexts"].size(), 0, "and stamps nothing")
