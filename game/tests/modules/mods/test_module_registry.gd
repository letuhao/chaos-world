extends TestCase

## The runtime module registry behind ctx.register_module (ADR 0184):
## named-cause validation and a deterministic attach order.

const REAL_API := "res://src/modules/mods/api.gd"


func _reg() -> ModuleRegistry:
	return ModuleRegistry.new()


func test_valid_chain_registers_and_orders() -> void:
	var reg := _reg()
	assert_eq(reg.register("m1", REAL_API, PackedStringArray())["ok"], true, "m1 ok")
	assert_eq(reg.register("m4", REAL_API, PackedStringArray())["ok"], true, "m4 ok")
	assert_eq(reg.register("m2", REAL_API, PackedStringArray(["m1"]))["ok"], true, "m2 ok")
	assert_eq(reg.register("m5", REAL_API, PackedStringArray(["m1"]))["ok"], true, "m5 ok")
	assert_eq(reg.register("m3", REAL_API, PackedStringArray(["m2"]))["ok"], true, "m3 ok")
	var out := reg.order()
	assert_eq(out["ok"], true, "order resolves")
	var want: Array[String] = []
	for name in out["order"]:
		if String(name).begins_with("m"):
			want.append(String(name))
	# Ties by first-registered: m1/m4 (index 0) before m2/m5; m2 before m5
	# (both wait on m1, m2 registered earlier); m3 last (waits on m2).
	assert_eq(
		want, ["m1", "m4", "m2", "m5", "m3"], "attach order is topological, ties by registration"
	)
	assert_eq(reg.api_path_of("m2"), REAL_API, "api path round-trips")
	assert_eq(reg.api_path_of("nope"), "", "unknown name has no api path")


func test_unknown_dependency_names_both_ends() -> void:
	var reg := _reg()
	assert_eq(reg.register("m1", REAL_API, PackedStringArray())["ok"], true, "m1 ok")
	assert_eq(
		reg.register("m2", REAL_API, PackedStringArray(["ghost"]))["ok"],
		true,
		"forward rows record"
	)
	var out := reg.order()
	assert_eq(out["ok"], false, "order refuses")
	assert_eq(out["reason"], "unknown_dependency", "named cause")
	assert_eq(String(out["detail"]).contains("m2"), true, "names the dependent")
	assert_eq(String(out["detail"]).contains("ghost"), true, "names the missing dep")


func test_dependency_cycle_names_every_member() -> void:
	var reg := _reg()
	assert_eq(reg.register("m_a", REAL_API, PackedStringArray(["m_b"]))["ok"], true, "m_a ok")
	assert_eq(reg.register("m_b", REAL_API, PackedStringArray(["m_a"]))["ok"], true, "m_b ok")
	assert_eq(reg.register("m_c", REAL_API, PackedStringArray(["m_a"]))["ok"], true, "m_c ok")
	var out := reg.order()
	assert_eq(out["ok"], false, "order refuses")
	assert_eq(out["reason"], "dependency_cycle", "named cause")
	assert_eq(String(out["detail"]).contains("m_a"), true, "member m_a named")
	assert_eq(String(out["detail"]).contains("m_b"), true, "member m_b named")
	assert_eq(String(out["detail"]).contains("m_c"), true, "dependent m_c named")


func test_self_dependency_is_a_cycle() -> void:
	var reg := _reg()
	var out := reg.register("selfish", REAL_API, PackedStringArray(["selfish"]))
	assert_eq(out["ok"], false, "refused at register")
	assert_eq(out["reason"], "dependency_cycle", "named cause")
	assert_eq(String(out["detail"]).contains("selfish"), true, "member named")


func test_duplicate_module_refused() -> void:
	var reg := _reg()
	assert_eq(reg.register("dup", REAL_API, PackedStringArray())["ok"], true, "first wins")
	var out := reg.register("dup", REAL_API, PackedStringArray())
	assert_eq(out["ok"], false, "second refused")
	assert_eq(out["reason"], "duplicate_module", "named cause")
	var seeded := _reg()
	var clash := seeded.register("items", REAL_API, PackedStringArray())
	assert_eq(clash["ok"], false, "a base name cannot be re-registered")
	assert_eq(clash["reason"], "duplicate_module", "named cause")


func test_bad_api_path_refused() -> void:
	var reg := _reg()
	var out := reg.register("m1", "res://src/modules/mods/no_such_api.gd", PackedStringArray())
	assert_eq(out["ok"], false, "refused")
	assert_eq(out["reason"], "bad_api_path", "named cause")


func test_layer_deps_are_implicitly_satisfied() -> void:
	var reg := _reg()
	assert_eq(
		reg.register("m1", REAL_API, PackedStringArray(["contracts", "core"]))["ok"],
		true,
		"layer deps accepted"
	)
	assert_eq(reg.order()["ok"], true, "and they never count as unknown")


func test_order_is_deterministic() -> void:
	var first := _reg()
	var second := _reg()
	for reg in [first, second]:
		reg.register("boot", REAL_API, PackedStringArray(["items", "soul"]))
		reg.register("ui", REAL_API, PackedStringArray(["boot"]))
		reg.register("save", REAL_API, PackedStringArray([]))
	assert_eq(first.order()["order"], second.order()["order"], "same registrations, same order")
	assert_eq(first.order()["ok"], true, "order resolves")


func test_seed_list_resolves_in_registry_json() -> void:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/").simplify_path()
	var text := FileAccess.get_file_as_string(root.path_join("tools/arch/registry.json"))
	assert_eq(text != "", true, "registry.json readable via FileAccess")
	var parsed = JSON.parse_string(text)
	assert_eq(parsed is Dictionary, true, "registry.json parses")
	var modules: Dictionary = parsed["modules"]
	for name in ModuleRegistry.BASE_DEPS:
		assert_eq(modules.has(name), true, "seed module '%s' is in registry.json" % name)
	assert_eq(
		ModuleRegistry.BASE_DEPS.size(),
		modules.size(),
		"seed list and registry.json cover the same modules"
	)
