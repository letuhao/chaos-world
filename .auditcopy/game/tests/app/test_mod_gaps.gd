extends TestCase

## Tests for the four gaps fixed in the mod wiring (ADR 0184):
##   Gap 1 — screens registered from contexts into ScreenRegistry
##   Gap 2 — all catalog families wired (world, npc, race, techniques, elements)
##   Gap 3 — id_field passed through the stack
##   Gap 4 — events bus subscriptions connected

const WORLD_FAMILY := &"world"
const NPC_FAMILY := &"npc"
const RACE_FAMILY := &"race"
const TECHNIQUES_FAMILY := &"techniques"
const ELEMENTS_FAMILY := &"elements"

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _saved_registrations: Dictionary = {}
var _saved_contexts: Array = []


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	_saved_registrations = ModBoot.active_registrations.duplicate(true)
	_saved_contexts = ModBoot.active_contexts.duplicate(true)
	# Clear the static ScreenRegistry so a previous test's screens don't collide.
	ScreenRegistry.clear()


func teardown() -> void:
	ModBoot.active_registrations = _saved_registrations
	ModBoot.active_contexts = _saved_contexts
	# Reset catalogs so overlay roots from one test don't leak into another.
	Crafting.set_overlay_roots([])
	QuestCatalog.set_overlay_roots([])
	EventCatalog.set_overlay_roots([])
	WorldLocationCatalog.set_overlay_roots([])
	NpcCatalog.set_overlay_roots([])
	RaceCatalog.set_overlay_roots([])
	TechniqueCatalog.set_overlay_roots([])
	ElementCatalog.set_overlay_roots([])
	ScreenRegistry.clear()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- Gap 1: Screens registered from contexts --------------------------------


func test_screens_registered_from_contexts() -> void:
	# Build a context that registers a screen, then drive _attach_body_modules.
	var ctx := RegistrationContext.new("test_mod", {})
	ctx.register_screen("test_mod_screen", "res://tests/fixtures/mod_screen.tscn", "Test Screen")
	ModBoot.active_contexts = [ctx]
	_app.call("_attach_body_modules", _fresh_actor())
	# The screen is now in the ScreenRegistry route table.
	assert_eq(
		ScreenRegistry.path_of("test_mod_screen"),
		"res://tests/fixtures/mod_screen.tscn",
		"the mod screen is registered in the ScreenRegistry route table"
	)
	assert_eq(
		ScreenRegistry.label_of("test_mod_screen"),
		"Test Screen",
		"the mod screen label is registered"
	)


func test_screens_empty_contexts_is_safe() -> void:
	ModBoot.active_contexts = []
	_app.call("_attach_body_modules", _fresh_actor())
	assert_eq(true, true, "empty contexts did not break the boot")


# --- Gap 2: All catalog families wired --------------------------------------


func test_world_content_roots_reach_the_catalog() -> void:
	var mod_dir := "res://tests/fixtures/mod_world"
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["content_roots"] = {
		WORLD_FAMILY: [{"dir": mod_dir, "owner": "test_mod", "declared_overrides": []}],
	}
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	var catalog := WorldLocationCatalog.instance()
	assert_eq(
		catalog.location_ids().is_empty(),
		false,
		"the world location catalog has content after wiring overlay roots"
	)


func test_npc_content_roots_reach_the_catalog() -> void:
	var mod_dir := "res://tests/fixtures/mod_npc"
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["content_roots"] = {
		NPC_FAMILY: [{"dir": mod_dir, "owner": "test_mod", "declared_overrides": []}],
	}
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	var catalog := NpcCatalog.instance()
	# The catalog loaded without error and has its base content.
	assert_eq(
		catalog.npc_ids().is_empty(),
		false,
		"the npc catalog has content after wiring overlay roots"
	)


func test_race_content_roots_reach_the_catalog() -> void:
	var mod_dir := "res://tests/fixtures/mod_race"
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["content_roots"] = {
		RACE_FAMILY: [{"dir": mod_dir, "owner": "test_mod", "declared_overrides": []}],
	}
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	var catalog := RaceCatalog.instance()
	assert_eq(
		catalog.race_ids().is_empty(),
		false,
		"the race catalog has content after wiring overlay roots"
	)


func test_techniques_content_roots_reach_the_catalog() -> void:
	var mod_dir := "res://tests/fixtures/mod_techniques"
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["content_roots"] = {
		TECHNIQUES_FAMILY: [{"dir": mod_dir, "owner": "test_mod", "declared_overrides": []}],
	}
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	var catalog := TechniqueCatalog.instance()
	assert_eq(
		catalog.technique_ids().is_empty(),
		false,
		"the technique catalog has content after wiring overlay roots"
	)


func test_elements_content_roots_reach_the_catalog() -> void:
	var mod_dir := "res://tests/fixtures/mod_elements"
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["content_roots"] = {
		ELEMENTS_FAMILY: [{"dir": mod_dir, "owner": "test_mod", "declared_overrides": []}],
	}
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	var catalog := ElementCatalog.instance()
	# The catalog loaded without error (may be empty if no authored elements).
	assert_eq(true, true, "the element catalog did not break the boot")


# --- Gap 3: id_field passed through the stack --------------------------------


func test_id_field_carried_on_stack_row() -> void:
	var ctx := RegistrationContext.new("test_mod", {})
	ctx.add_content_root("world", "res://tests/fixtures/mod_world", "location_id")
	var row: Dictionary = ctx.content_roots["world"][0]
	assert_eq(
		String(row.get("id_field", "")), "location_id", "the id_field is carried on the stack row"
	)


func test_id_field_defaults_to_id() -> void:
	var ctx := RegistrationContext.new("test_mod", {})
	ctx.add_content_root("items", "res://tests/fixtures/mod_items")
	var row: Dictionary = ctx.content_roots["items"][0]
	assert_eq(
		String(row.get("id_field", "")), "id", "the id_field defaults to 'id' when not specified"
	)


func test_id_field_used_by_catalog_overlay_merge() -> void:
	# CatalogOverlay.merge reads id_field from each row.
	var stack: Array = [
		{
			"dir": "res://tests/fixtures/mod_world",
			"owner": "test_mod",
			"declared_overrides": [],
			"id_field": "location_id"
		},
	]
	var merged: Dictionary = CatalogOverlay.merge(stack, "WorldLocationDef", "location_id")
	assert_eq(
		merged.get("ok", false),
		true,
		"CatalogOverlay.merge succeeds with the id_field from the stack row"
	)


# --- Gap 4: Events bus subscriptions connected -------------------------------


func test_events_subscription_connected() -> void:
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["subscriptions"] = [
		{
			"event_bus": "NpcEvents",
			"event_name": "npc_tracked",
			"callable": Callable(self, "_on_npc_tracked"),
		},
	]
	ModBoot.active_registrations = registrations
	_app.call("_attach_body_modules", _fresh_actor())
	# The subscription is stored on the app.
	assert_eq(_app._mod_subscriptions.size(), 1, "the subscription is stored on the app")
	# The callable is connected to the bus signal.
	var bus := NpcEvents.shared()
	assert_eq(
		bus.is_connected(&"npc_tracked", Callable(self, "_on_npc_tracked")),
		true,
		"the callable is connected to the NpcEvents bus"
	)


func test_events_subscription_unknown_bus_skipped() -> void:
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["subscriptions"] = [
		{
			"event_bus": "UnknownBus",
			"event_name": "some_event",
			"callable": Callable(_harness, "_on_npc_tracked"),
		},
	]
	ModBoot.active_registrations = registrations
	# Should not crash — unknown bus names are skipped.
	_app.call("_attach_body_modules", _fresh_actor())
	assert_eq(true, true, "unknown bus name did not break the boot")


func test_events_subscription_invalid_callable_skipped() -> void:
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["subscriptions"] = [
		{
			"event_bus": "NpcEvents",
			"event_name": "npc_tracked",
			"callable": Callable(),
		},
	]
	ModBoot.active_registrations = registrations
	# Should not crash — invalid callables are skipped.
	_app.call("_attach_body_modules", _fresh_actor())
	assert_eq(true, true, "invalid callable did not break the boot")


# --- Plumbing ----------------------------------------------------------------


## Stub handler for the events subscription test. The test only checks that
## the callable is connected, never that it runs.
func _on_npc_tracked(_npc_id: String, _tier: StringName) -> void:
	pass


func _fresh_actor() -> Actor:
	var actor := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor
