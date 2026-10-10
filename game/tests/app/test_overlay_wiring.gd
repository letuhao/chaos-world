class_name TestOverlayWiring
extends TestCase

## Tests that the remaining 4 content families (item_options, sects,
## sect_doctrines, fates) are wired into their catalogs via `set_overlay_roots`
## (ADR 0184 §5, ADR 0240), and that the events bus factory is OPEN —
## mod-registered custom bus types resolve dynamically (ADR 0242).

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _saved_registrations: Dictionary = {}


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	_saved_registrations = ModBoot.active_registrations.duplicate(true)


func teardown() -> void:
	ModBoot.active_registrations = _saved_registrations
	RegistrationContext._custom_buses.clear()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- Remaining families wired -------------------------------------------------


func test_remaining_families_have_overlay_methods() -> void:
	# Production wires each catalog with an explicit `<Class>.set_overlay_roots`
	# arm in `item_workbench_wiring.gd::wire_content_roots` (moved out of the body
	# when it hit the line ceiling), so the wiring is read off that text rather than
	# through `ClassDB`: the engine's class database does not resolve GDScript globals
	# (`class_exists` is false for every real catalog), and every `ClassDB` spelling of
	# this check fails on classes that compile, load and run. A missing arm here is the
	# unwired family.
	var body := _code_of("res://src/app/item_workbench_wiring.gd")
	assert_ne(body, "", "the production wiring source is readable")
	var catalogs: Array[String] = [
		"OptionCatalog",
		"SectCatalog",
		"SectDoctrineCatalog",
		"FateCatalog",
		"InstitutionDefCatalog",
		"StatusCatalog",
		"SoulCatalog",
		"SetCatalog",
		"NationCatalog",
		"ShopCatalog",
		"ClanCatalog",
		"ResourceNodeCatalog",
		"WeaponKindCatalog",
		"MaterialArtCatalog",
		"InjuryCatalog",
		"BloodlineCatalog",
		"AnchorCatalog",
		"DifficultyCatalog",
	]
	for catalog_name in catalogs as Array[String]:
		assert_ne(
			body.find("%s.set_overlay_roots(" % catalog_name),
			-1,
			"Catalog '%s' is wired in _wire_content_roots" % catalog_name
		)


func test_wire_content_roots_has_match_arms() -> void:
	var body := _code_of("res://src/app/item_workbench_wiring.gd")
	var start := body.find("func wire_content_roots(")
	assert_ne(start, -1, "the wiring function is still there")
	if start < 0:
		return
	# Bounded by the next top-level function. `static func`, because every verb in the
	# wiring file is static — a bound on `\nfunc ` finds nothing there and would leave
	# the arm check below vacuous.
	var stop := body.find("\nstatic func ", start + 1)
	assert_ne(stop, -1, "and there is a function after it to bound the slice")
	if stop < 0:
		return
	var wiring := body.substr(start, stop - start)
	for family in [
		"item_options",
		"sects",
		"sect_doctrines",
		"fates",
		"destinies",
		"institutions",
		"statuses",
		"soul_arrivals",
		"sets",
		"nations",
		"nation_territories",
		"market_shops",
		"clans",
		"holdings",
		"body_weapons",
		"body_material_arts",
		"body_injury_tuning",
		"bloodlines",
		"anchors",
		"difficulty",
	]:
		assert_ne(
			wiring.find('&"%s":' % family),
			-1,
			"wire_content_roots should have a match arm for '%s'" % family
		)


func test_set_overlay_roots_accepts_stack() -> void:
	var stack: Array = [
		{"dir": "res://mod_data/test_options", "owner": "test_mod", "declared_overrides": []},
	]
	OptionCatalog.set_overlay_roots(stack)
	# The stack is consumable, not just stored: a merge over it returns the
	# shape whether or not the dir exists. Instance call: this catalog merges
	# through its singleton rather than a static. Reset after: static state
	# persists across suites in one process.
	var merged := OptionCatalog.instance()._overlay_merge()
	assert_eq(bool(merged.has("ok")), true, "a merge over the accepted stack reports its shape")
	OptionCatalog.set_overlay_roots([])
	SectCatalog.set_overlay_roots(stack)
	SectCatalog.set_overlay_roots([])
	SectDoctrineCatalog.set_overlay_roots(stack)
	SectDoctrineCatalog.set_overlay_roots([])
	FateCatalog.set_overlay_roots(stack)
	FateCatalog.set_overlay_roots([])
	InstitutionDefCatalog.set_overlay_roots(stack)
	InstitutionDefCatalog.set_overlay_roots([])
	StatusCatalog.set_overlay_roots(stack)
	StatusCatalog.set_overlay_roots([])
	SoulCatalog.set_overlay_roots(stack)
	SoulCatalog.set_overlay_roots([])
	SetCatalog.set_overlay_roots(stack)
	SetCatalog.set_overlay_roots([])
	NationCatalog.set_overlay_roots(stack)
	NationCatalog.set_overlay_roots([])
	ShopCatalog.set_overlay_roots(stack)
	ShopCatalog.set_overlay_roots([])
	ClanCatalog.set_overlay_roots(stack)
	ClanCatalog.set_overlay_roots([])
	ResourceNodeCatalog.set_overlay_roots(stack)
	ResourceNodeCatalog.set_overlay_roots([])
	WeaponKindCatalog.set_overlay_roots(stack)
	WeaponKindCatalog.set_overlay_roots([])
	MaterialArtCatalog.set_overlay_roots(stack)
	MaterialArtCatalog.set_overlay_roots([])
	InjuryCatalog.set_overlay_roots(stack)
	InjuryCatalog.set_overlay_roots([])
	BloodlineCatalog.set_overlay_roots(stack)
	BloodlineCatalog.set_overlay_roots([])
	AnchorCatalog.set_overlay_roots(stack)
	AnchorCatalog.set_overlay_roots([])
	DifficultyCatalog.set_overlay_roots(stack)
	DifficultyCatalog.set_overlay_roots([])


# --- Events bus factory is OPEN ------------------------------------------------


func test_custom_bus_type_registered_and_resolved() -> void:
	var custom_bus := RefCounted.new()
	RegistrationContext.register_events_bus("MyCustomEvents", func(): return custom_bus)
	assert_eq(
		RegistrationContext.has_custom_bus("MyCustomEvents"),
		true,
		"custom bus should be registered"
	)
	var resolved: RefCounted = _app.call("_resolve_events_bus", "MyCustomEvents")
	assert_eq(resolved, custom_bus, "custom bus resolves to the factory's instance")
	# NO `free()`: a RefCounted is released by its reference count, so `free()` on one is
	# the engine error "Attempted to free a RefCounted object" and frees nothing at all.
	# What needed clearing is the REGISTRY entry, and `setup()` clears it for every case.


func test_custom_bus_takes_priority_over_classdb() -> void:
	# Register a custom bus with the same name as a ClassDB class.
	# The custom registration should win.
	var custom_bus := RefCounted.new()
	RegistrationContext.register_events_bus("NpcEvents", func(): return custom_bus)
	var resolved: RefCounted = _app.call("_resolve_events_bus", "NpcEvents")
	assert_eq(resolved, custom_bus, "custom bus takes priority over ClassDB resolution")
	# No `free()` — see the note in `test_custom_bus_type_registered_and_resolved`.


func test_unknown_bus_returns_null() -> void:
	var resolved: RefCounted = _app.call("_resolve_events_bus", "TotallyUnknownBus")
	assert_eq(resolved, null, "unknown bus name returns null")


func test_classdb_bus_with_shared_resolves_to_shared() -> void:
	# NpcEvents has a shared() accessor — it should resolve to the shared instance.
	var resolved: RefCounted = _app.call("_resolve_events_bus", "NpcEvents")
	assert_ne(resolved, null, "NpcEvents resolves to a bus")
	assert_eq(resolved, NpcEvents.shared(), "NpcEvents resolves to the shared instance")


func test_classdb_bus_without_accessor_instantiates() -> void:
	# WorldEvents has no shared() or events() accessor — it should be instantiated.
	var resolved: RefCounted = _app.call("_resolve_events_bus", "WorldEvents")
	assert_ne(resolved, null, "WorldEvents resolves to a bus")
	var script: Script = resolved.get_script()
	assert_ne(script, null, "WorldEvents resolves to a scripted object")
	assert_eq(
		String(script.get_global_name()),
		"WorldEvents",
		"WorldEvents resolves to the contract of that name"
	)


# --- Helpers ------------------------------------------------------------------


func _code_of(path: String) -> String:
	var out := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out
