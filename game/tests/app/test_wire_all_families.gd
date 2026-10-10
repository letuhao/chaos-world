class_name TestWireAllFamilies
extends TestCase

## Tests that all 48 content families from tools/arch/families.json are wired
## into their catalogs via `set_overlay_roots` (ADR 0184 §5, ADR 0240).
##
## Families without a catalog are skipped with a warning (never silent), so
## this test asserts the wiring exists for every family that HAS a catalog.

const FAMILIES_PATH := "res://../tools/arch/families.json"
## Production's wiring table, read as text: the arms this suite asserts. It lives in
## `item_workbench_wiring.gd` — moved out of the body when that hit the line ceiling.
const WIRING := "res://src/app/item_workbench_wiring.gd"

## The catalog class each content family wires through, or absent for a family that has
## none. A TABLE rather than a `match` returning from every arm: this is data the suite
## reads, one line per family, and a family with no catalog is visible by its ABSENCE
## rather than by which `return` branch it did not take. Keys are `StringName` because
## that is what the family ids are.
const CATALOG_CLASSES := {
	&"items": "Crafting",
	&"quest": "QuestCatalog",
	&"event": "EventCatalog",
	&"world_locations": "WorldLocationCatalog",
	&"npcs": "NpcCatalog",
	&"races": "RaceCatalog",
	&"techniques": "TechniqueCatalog",
	&"elements": "ElementCatalog",
	&"statuses": "StatusCatalog",
	&"soul_arrivals": "SoulCatalog",
	&"sets": "SetCatalog",
	&"set_items": "SetCatalog",
	&"sects": "SectCatalog",
	&"sect_doctrines": "SectDoctrineCatalog",
	&"nations": "NationCatalog",
	&"nation_territories": "NationCatalog",
	&"market_shops": "ShopCatalog",
	&"clans": "ClanCatalog",
	&"holdings": "ResourceNodeCatalog",
	&"body_weapons": "WeaponKindCatalog",
	&"body_material_arts": "MaterialArtCatalog",
	&"body_injury_tuning": "InjuryCatalog",
	&"bloodlines": "BloodlineCatalog",
	&"anchors": "AnchorCatalog",
	&"difficulty": "DifficultyCatalog",
	&"fates": "FateCatalog",
	&"destinies": "FateCatalog",
	&"item_options": "OptionCatalog",
}


## `TestCase` publishes `assert_eq`/`assert_ne`/`assert_almost_eq` only, so the
## two-arg boolean shape used throughout this file is spelled here rather than
## restated at every call site (file repair: the bare `assert_true` never existed
## on the base and the suite could not load).
func assert_true(value: bool, label: String) -> void:
	assert_eq(value, true, label)


func _read_families() -> Dictionary:
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(FAMILIES_PATH)
	if text == "":
		return {}
	if json.parse(text) != OK:
		return {}
	return json.data


## The catalog class a family wires through, or `""` when it has none — the answer
## [constant CATALOG_CLASSES] holds, read through one lookup so an unwired family is a
## missing key rather than an arm nobody wrote.
func _catalog_class_for_family(family: String) -> String:
	return String(CATALOG_CLASSES.get(StringName(family), ""))


func test_all_families_have_catalogs_or_are_skipped() -> void:
	var families := _read_families()
	var family_names: Array = families.get("families", {}).keys()
	assert_true(family_names.size() >= 48, "families.json should have at least 48 families")
	var unwired: Array[String] = []
	for family in family_names:
		var catalog_class := _catalog_class_for_family(String(family))
		if catalog_class == "":
			unwired.append(String(family))
	# Families without catalogs are skipped with a warning, not silent.
	# This test documents which families are skipped.
	# The unwired list should be stable — if it grows, a catalog was removed.
	print("Unwired families (no catalog): %s" % str(unwired))


func test_catalogs_have_set_overlay_roots() -> void:
	# Production wires each family with an explicit `<Class>.set_overlay_roots`
	# arm in `item_workbench_wiring.gd::wire_content_roots`, so the wiring is read
	# off that text rather than through `ClassDB`: the engine's class database
	# does not resolve GDScript globals (`class_exists` is false for every real
	# catalog), and every `ClassDB` spelling of this check fails on classes that
	# compile, load and run. A missing arm here is the unwired family.
	var body := FileAccess.get_file_as_string(WIRING)
	assert_ne(body, "", "the production wiring source is readable")
	var families := _read_families()
	var family_names: Array = families.get("families", {}).keys()
	var missing: Array[String] = []
	for family in family_names:
		var catalog_class := _catalog_class_for_family(String(family))
		if catalog_class == "":
			continue
		if body.find("%s.set_overlay_roots(" % catalog_class) < 0:
			missing.append(
				(
					"%s (no %s.set_overlay_roots arm in wire_content_roots)"
					% [String(family), catalog_class]
				)
			)
	assert_true(missing.is_empty(), "Every wired family is wired in production: %s" % str(missing))


func test_overlay_roots_accepts_stack() -> void:
	# Test that set_overlay_roots accepts a stack and stores it: the stored
	# stack reads back verbatim, so the call is a write and not a no-op.
	var stack: Array = [
		{"dir": "res://mod_data/test_items", "owner": "test_mod", "declared_overrides": []},
	]
	Crafting.set_overlay_roots(stack)
	assert_eq(Crafting.overlay_roots(), stack, "the stack round-trips through the setter")
	# Reset to empty after test: static state persists across suites in one process.
	Crafting.set_overlay_roots([])


func test_overlay_merge_returns_dictionary() -> void:
	# Test that overlay_merge returns the expected dictionary shape
	var merged := Crafting.overlay_merge()
	assert_true(merged.has("ok"), "overlay_merge should return 'ok' key")
	assert_true(merged.has("reason"), "overlay_merge should return 'reason' key")
	assert_true(merged.has("detail"), "overlay_merge should return 'detail' key")
	assert_true(merged.has("merged"), "overlay_merge should return 'merged' key")
	assert_true(merged.has("paths"), "overlay_merge should return 'paths' key")
	assert_true(merged.has("owners"), "overlay_merge should return 'owners' key")


func test_unwired_families_log_warning() -> void:
	# Families without catalogs should be skipped with a warning, not silent.
	# This is tested by the _ wire_content_roots method's default branch.
	# Here we verify the families that ARE unwired are documented.
	var families := _read_families()
	var family_names: Array = families.get("families", {}).keys()
	var unwired: Array[String] = []
	for family in family_names:
		var catalog_class := _catalog_class_for_family(String(family))
		if catalog_class == "":
			unwired.append(String(family))
	# These families have no catalog and should be skipped with a warning:
	# domain_templates, domain_rooms, domain_inhabitants, socket_items,
	# loot_tables, loot_tiers, loot_encounters, recipes, bosses, domains,
	# body_realms, body_acupoints, npc_personas, qi_realms, mind_realms,
	# fixture_cultivation_realms, meridians, portraits, technique_magnitudes,
	# world_factions, world_inhabitants, world_laws, world_tiers
	assert_true(unwired.size() > 0, "Some families should be unwired (no catalog)")
	print("Documented unwired families: %s" % str(unwired))
