extends TestCase

## Mod-to-mod integration seams: register_mod_api / get_mod_api / check_for_update.
## A mod exposes an API object under a name; another mod resolves it through the
## shared API registry the loader injects into every context.

var _root: String = ""


func setup() -> void:
	_root = "user://mod_integrations_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
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


func _write_mod(dir_name: String, text: String) -> void:
	var dir_path := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _mod_json(id: String, version: String, priority: int, extra: String = "") -> String:
	return (
		'{"id": "%s", "version": "%s", "priority": %d, "requires_api": 1%s}'
		% [id, version, priority, extra]
	)


func test_register_and_get_mod_api() -> void:
	_write_mod("provider", _mod_json("provider", "1.0", 0))
	_write_mod("consumer", _mod_json("consumer", "1.0", 0))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "load succeeds")
	var contexts: Array = out["contexts"]
	assert_eq(contexts.size(), 2, "two contexts")
	# Load order is alphabetical at same priority: consumer, then provider
	var consumer_ctx: RegistrationContext = contexts[0]
	var provider_ctx: RegistrationContext = contexts[1]
	# The provider registers an API object
	var api_obj := RefCounted.new()
	provider_ctx.register_mod_api("test_api", api_obj)
	# The consumer resolves it
	var resolved: Object = consumer_ctx.get_mod_api("provider", "test_api")
	assert_eq(resolved != null, true, "api resolved")
	assert_eq(resolved == api_obj, true, "same object returned")


func test_get_mod_api_returns_null_for_unloaded_mod() -> void:
	_write_mod("consumer", _mod_json("consumer", "1.0", 0))
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var resolved: Object = ctx.get_mod_api("nonexistent", "test_api")
	assert_eq(resolved, null, "null for unloaded mod")


func test_get_mod_api_returns_null_for_unregistered_name() -> void:
	_write_mod("provider", _mod_json("provider", "1.0", 0))
	_write_mod("consumer", _mod_json("consumer", "1.0", 0))
	var out := ModsApi.load_order([_root])
	var consumer_ctx: RegistrationContext = out["contexts"][1]
	var resolved: Object = consumer_ctx.get_mod_api("provider", "no_such_api")
	assert_eq(resolved, null, "null for unregistered api name")


func test_check_for_update_stub_returns_no_update() -> void:
	_write_mod("demo", _mod_json("demo", "1.0", 0))
	var out := ModsApi.load_order([_root])
	var ctx: RegistrationContext = out["contexts"][0]
	var result: Dictionary = ctx.check_for_update()
	assert_eq(bool(result["has_update"]), false, "no update available")
	assert_eq(result["latest_version"], "", "no latest version")
	assert_eq(result["download_url"], "", "no download url")


func test_integrations_manifest_field_parses() -> void:
	var text := _mod_json(
		"demo", "1.0", 0,
		', "integrations": [{"target_mod": "other", "api_name": "data", "min_version": "1.2"}]'
	)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	var m: Dictionary = out["manifest"]
	assert_eq(m["integrations"].size(), 1, "one integration")
	assert_eq(String(m["integrations"][0]["target_mod"]), "other", "target_mod")
	assert_eq(String(m["integrations"][0]["api_name"]), "data", "api_name")
	assert_eq(String(m["integrations"][0]["min_version"]), "1.2", "min_version")


func test_integrations_manifest_field_optional() -> void:
	var text := _mod_json("demo", "1.0", 0)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	var m: Dictionary = out["manifest"]
	assert_eq(m["integrations"].size(), 0, "no integrations by default")


func test_update_url_manifest_field_parses() -> void:
	var text := _mod_json(
		"demo", "1.0", 0, ', "update_url": "https://example.com/update"'
	)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	assert_eq(String(out["manifest"]["update_url"]), "https://example.com/update", "url carried")


func test_update_url_manifest_field_optional() -> void:
	var text := _mod_json("demo", "1.0", 0)
	var out := ModsApi.parse_manifest(text, "user://demo/mod.json")
	assert_eq(bool(out["ok"]), true, "parse succeeds")
	assert_eq(String(out["manifest"]["update_url"]), "", "empty by default")
