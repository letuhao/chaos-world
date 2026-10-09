extends TestCase

## Real attach hook callables: a manifest's attach_hooks entry can specify
## a callable (script path + method name), and the loader binds it.

var _root: String = ""


func setup() -> void:
	_root = "user://w2_mod_hook_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root)


func teardown() -> void:
	_remove_tree(_root)
	_root = ""


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
	var depth_guard := 0
	var names: Array[String] = []
	while entry != "" and depth_guard < 4096:
		depth_guard += 1
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


## The one manifest shape these two cases share, with the attach hook's `callable`
## filled in only when one is named. JSON is built with `JSON.stringify` rather than
## written out as a literal so this stays under the 100-character line cap without
## retyping the payload the two cases depend on.
func _manifest(mod_id: String, hook: Dictionary) -> String:
	return (
		JSON
		. stringify(
			{
				"id": mod_id,
				"version": "1.0",
				"priority": 0,
				"requires_api": 1,
				"attach_hooks": [hook],
			}
		)
	)


func test_attach_hook_callable_fires() -> void:
	ModHookFixture.fired = false
	_write_mod(
		"hook_test",
		_manifest(
			"hook_test",
			{
				"phase": "test_phase",
				"callable": "res://src/modules/mods/hook_fixture.gd:on_attach",
			}
		)
	)
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "valid mod")
	var ctx: RegistrationContext = out["contexts"][0]
	var hook: Dictionary = ctx.attach_hooks[0]
	assert_eq(String(hook["phase"]), "test_phase", "phase recorded")
	var callable: Callable = hook["hook"]
	assert_eq(callable.is_valid(), true, "callable is valid")
	callable.call()
	assert_eq(ModHookFixture.fired, true, "callable fired")


func test_attach_hook_without_callable_is_an_empty_stub() -> void:
	_write_mod("stub_test", _manifest("stub_test", {"phase": "test_phase"}))
	var out := ModsApi.load_order([_root])
	assert_eq(bool(out["ok"]), true, "valid mod")
	var ctx: RegistrationContext = out["contexts"][0]
	var hook: Dictionary = ctx.attach_hooks[0]
	var callable: Callable = hook["hook"]
	assert_eq(callable.is_valid(), false, "empty stub is not valid")
