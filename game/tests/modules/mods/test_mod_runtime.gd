extends TestCase

## `ModRuntime.finalize` folds every mod's RegistrationContext into the boot's
## runtime registrations (ADR 0184): per-family content roots for the catalog
## overlay stack, the module attach order from the shared registry, and the
## screen routes and attach hooks the app pushes into the ScreenRegistry and
## the AttachPipeline. Same contexts in the same order, same result.

const REAL_API := "res://src/modules/mods/api.gd"


func setup() -> void:
	# The ctx seam forwards register_screen to the static ScreenRegistry, so each
	# test starts from an empty route table.
	ScreenRegistry.clear()


func teardown() -> void:
	ScreenRegistry.clear()


func _noop(_actor) -> void:
	pass


func _ctx(mod_id: String, registry: ModuleRegistry) -> RegistrationContext:
	return RegistrationContext.new(mod_id, {}, registry)


func test_finalize_aggregates_multiple_ctxs_in_load_order() -> void:
	var registry := ModuleRegistry.new()
	var a := _ctx("mod_a", registry)
	a.add_content_root("items", "res://a/items")
	a.add_content_root("recipes", "res://a/recipes")
	a.register_module("m_a", REAL_API, [])
	a.register_screen("scr_a", "res://a.tscn", "A")
	a.add_attach_hook("economy", Callable(self, "_noop"))
	var b := _ctx("mod_b", registry)
	b.add_content_root("items", "res://b/items")
	b.register_module("m_b", REAL_API, ["m_a"])
	b.register_screen("scr_b", "res://b.tscn", "B")
	b.add_attach_hook("combat", Callable(self, "_noop"))
	var out := ModRuntime.finalize([a, b], registry)
	# content_roots: per-family, merged in load order (a's items before b's).
	var items: Array = out["content_roots"]["items"]
	assert_eq(items.size(), 2, "two item roots merged")
	assert_eq(String(items[0]["dir"]), "res://a/items", "mod_a's items root first")
	assert_eq(String(items[0]["owner"]), "mod_a", "first root owned by mod_a")
	assert_eq(String(items[1]["dir"]), "res://b/items", "mod_b's items root second")
	assert_eq(String(items[1]["owner"]), "mod_b", "second root owned by mod_b")
	var recipes: Array = out["content_roots"]["recipes"]
	assert_eq(recipes.size(), 1, "one recipe root")
	assert_eq(String(recipes[0]["dir"]), "res://a/recipes", "recipe root from mod_a")
	assert_eq(String(recipes[0]["owner"]), "mod_a", "recipe root owned by mod_a")


func test_content_roots_carry_the_manifest_overrides() -> void:
	var registry := ModuleRegistry.new()
	var manifest := {"overrides": ["iron_sword"]}
	var ctx := RegistrationContext.new("mod_o", manifest, registry)
	ctx.add_content_root("items", "res://o/items")
	var out := ModRuntime.finalize([ctx], registry)
	var items: Array = out["content_roots"]["items"]
	assert_eq(items.size(), 1, "one root")
	assert_eq(items[0]["declared_overrides"], ["iron_sword"], "overrides ride the row")


func test_modules_come_from_the_shared_registry_order() -> void:
	var registry := ModuleRegistry.new()
	var a := _ctx("mod_a", registry)
	a.register_module("m_a", REAL_API, [])
	var b := _ctx("mod_b", registry)
	b.register_module("m_b", REAL_API, ["m_a"])
	var out := ModRuntime.finalize([a, b], registry)
	assert_eq(out["modules"]["ok"], true, "registry order resolves")
	assert_eq(out["modules"]["order"], ["m_a", "m_b"], "dependency orders before its dependent")


func test_screens_are_collected_with_scene_path() -> void:
	var registry := ModuleRegistry.new()
	var a := _ctx("mod_a", registry)
	a.register_screen("scr_a", "res://a.tscn", "A")
	var b := _ctx("mod_b", registry)
	b.register_screen("scr_b", "res://b.tscn", "B")
	var out := ModRuntime.finalize([a, b], registry)
	assert_eq(out["screens"].size(), 2, "both screens collected")
	assert_eq(String(out["screens"][0]["id"]), "scr_a", "first screen id")
	assert_eq(String(out["screens"][0]["scene_path"]), "res://a.tscn", "first screen path")
	assert_eq(String(out["screens"][0]["label"]), "A", "first screen label")
	assert_eq(String(out["screens"][1]["id"]), "scr_b", "second screen id")
	assert_eq(String(out["screens"][1]["scene_path"]), "res://b.tscn", "second screen path")


func test_attach_hooks_are_collected_with_callable() -> void:
	var registry := ModuleRegistry.new()
	var hook_a := Callable(self, "_noop")
	var hook_b := Callable(self, "_noop")
	var a := _ctx("mod_a", registry)
	a.add_attach_hook("economy", hook_a)
	var b := _ctx("mod_b", registry)
	b.add_attach_hook("combat", hook_b)
	var out := ModRuntime.finalize([a, b], registry)
	assert_eq(out["attach_hooks"].size(), 2, "both hooks collected")
	assert_eq(String(out["attach_hooks"][0]["phase"]), "economy", "first hook phase")
	assert_eq(out["attach_hooks"][0]["callable"], hook_a, "first hook callable preserved")
	assert_eq(String(out["attach_hooks"][1]["phase"]), "combat", "second hook phase")
	assert_eq(out["attach_hooks"][1]["callable"], hook_b, "second hook callable preserved")


func test_finalize_skips_a_null_context() -> void:
	var registry := ModuleRegistry.new()
	var a := _ctx("mod_a", registry)
	a.add_content_root("items", "res://a/items")
	var out := ModRuntime.finalize([a, null], registry)
	assert_eq(out["content_roots"]["items"].size(), 1, "only the live ctx contributes")
	assert_eq(out["screens"].size(), 0, "no screens from a null ctx")
	assert_eq(out["attach_hooks"].size(), 0, "no hooks from a null ctx")


func test_finalize_on_no_contexts_returns_empty_collections() -> void:
	var registry := ModuleRegistry.new()
	var out := ModRuntime.finalize([], registry)
	assert_eq(out["content_roots"].size(), 0, "no families")
	assert_eq(out["modules"]["ok"], true, "empty registry still orders clean")
	assert_eq(out["modules"]["order"].size(), 0, "no modules")
	assert_eq(out["screens"].size(), 0, "no screens")
	assert_eq(out["attach_hooks"].size(), 0, "no hooks")
