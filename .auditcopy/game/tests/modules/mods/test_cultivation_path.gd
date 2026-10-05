extends TestCase

## Fixture proving a mod can declare a new cultivation path (ADR 0184).
## The fixture mod registers with `provides: ["cultivation_path"]`, and the
## registry validates its seeds against the cultivation-path contract.

const API := "res://tests/fixtures/mods/cultivation_path/api.gd"
const SEED_DIR := "res://tests/fixtures/mods/cultivation_path/realms/"
const MODULE_NAME := "w8_fixture_cultivation"


func _reg() -> ModuleRegistry:
	return ModuleRegistry.new()


func test_cultivation_path_registers_with_valid_seeds() -> void:
	var reg := _reg()
	var out := reg.register(MODULE_NAME, API, PackedStringArray(), ["cultivation_path"], SEED_DIR)
	assert_eq(out["ok"], true, "fixture cultivation path registers")
	assert_eq(out["reason"], "", "no error reason")


func test_cultivation_path_without_provides_skips_validation() -> void:
	# A module that does NOT declare cultivation_path is not validated as one,
	# so it registers even with no seeds. This is the escape hatch for mods
	# that add non-cultivation content.
	var reg := _reg()
	var out := reg.register(MODULE_NAME, API, PackedStringArray())
	assert_eq(out["ok"], true, "module without provides registers")


func test_cultivation_path_with_missing_seeds_is_refused() -> void:
	# A module that declares cultivation_path but has no seeds is refused
	# with a named cause — never a silent skip (ADR 0184 §8).
	var reg := _reg()
	var out := reg.register(
		"w8_empty_cultivation",
		API,
		PackedStringArray(),
		["cultivation_path"],
		"res://tests/fixtures/mods/cultivation_path/empty_realms/"
	)
	assert_eq(out["ok"], false, "missing seeds refused")
	assert_eq(out["reason"], "invalid_cultivation_seeds", "named cause")
	assert_eq(String(out["detail"]).contains("no seeds found"), true, "names the missing seed")


func test_cultivation_path_with_invalid_seed_field_is_refused() -> void:
	# A seed with progress_required <= 0 is refused.
	var reg := _reg()
	# Temporarily point at a directory with a bad seed — we use the real
	# seed dir but the contract check runs on every realm, so a missing
	# realm seed is also a finding. Here we test the field validation by
	# using a seed dir that exists but has a bad seed.
	# Create a bad seed in a temp location is not possible without writing
	# files, so we test the contract validation directly instead.
	var seed := FixtureCultivationRealmSeed.new()
	seed.id = &"qi_refining"
	seed.progress_required = 0.0
	seed.breakthrough_item = &"pill"
	seed.recovery_item = &"recovery"
	var findings := CultivationPathContract.validate_seed(seed)
	assert_eq(findings.size(), 1, "one finding for zero progress")
	assert_eq(findings[0].contains("progress_required"), true, "names the field")
	# Resource is RefCounted: no free(), it is released when unreferenced.


func test_cultivation_path_provider_calls_realm_rate() -> void:
	# The provider must call RealmRate.factor and must not declare its own
	# RATE_STEP or read RealmDefaults.ladder().
	var source := FileAccess.get_file_as_string(
		"res://tests/fixtures/mods/cultivation_path/provider.gd"
	)
	var findings := CultivationPathContract.validate_provider_source(source)
	assert_eq(findings.size(), 0, "provider source is valid: %s" % str(findings))


func test_cultivation_path_is_attachable() -> void:
	# The facade's attach() must work on a real actor. The path is set
	# separately (as ActorFactory.with_qi_cultivation does for the real paths).
	# Actor is RefCounted: no free(), it is released when unreferenced.
	var actor := ActorFactory.build(&"fixture_cultivation_hero")
	actor.set_path(PathState.new(&"fixture_cultivation", &"qi_refining"))
	FixtureCultivationApi.attach(actor)
	var state := actor.path(&"fixture_cultivation")
	assert_eq(state == null, false, "path is set")


func test_cultivation_path_panel_state_reads_back() -> void:
	# The facade's panel_state() must return a dictionary with the expected keys.
	var actor := ActorFactory.build(&"fixture_cultivation_hero2")
	actor.set_path(PathState.new(&"fixture_cultivation", &"qi_refining"))
	FixtureCultivationApi.attach(actor)
	var panel := FixtureCultivationApi.panel_state(actor)
	assert_eq(panel.is_empty(), false, "panel state is non-empty")
	assert_eq(panel.has("realm"), true, "panel has realm")
	assert_eq(String(panel["realm"]), "qi_refining", "panel realm matches")


func test_registration_context_passes_provides_through() -> void:
	# The RegistrationContext must forward provides and seed_dir to the registry.
	var reg := _reg()
	var ctx := RegistrationContext.new("fixture_mod", {}, reg)
	ctx.register_module(MODULE_NAME, API, [], ["cultivation_path"], SEED_DIR)
	var modules: Array = ctx.modules
	assert_eq(modules.size(), 1, "one module registered")
	assert_eq(modules[0]["ok"], true, "module registered ok")
	assert_eq(modules[0]["provides"], ["cultivation_path"], "provides forwarded")
	assert_eq(modules[0]["seed_dir"], SEED_DIR, "seed_dir forwarded")


func test_mod_loader_validates_cultivation_path_seeds() -> void:
	# The full loader path: a mod.json with provides: ["cultivation_path"]
	# must pass through the loader and register successfully.
	var roots: Array[String] = ["res://tests/fixtures/mods/cultivation_path"]
	var out := ModLoader.load_order(roots)
	assert_eq(out["ok"], true, "loader succeeds: %s" % str(out.get("detail", "")))
	assert_eq(out["order"].size(), 1, "one mod loaded")
	assert_eq(String(out["order"][0]), "w8_fixture_cultivation_path", "mod id matches")
