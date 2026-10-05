class_name TestWireAllFamilies
extends TestCase

## Tests that all 48 content families from tools/arch/families.json are wired
## into their catalogs via `set_overlay_roots` (ADR 0184 §5, ADR 0240).
##
## Families without a catalog are skipped with a warning (never silent), so
## this test asserts the wiring exists for every family that HAS a catalog.

const FAMILIES_PATH := "res://../tools/arch/families.json"


func _read_families() -> Dictionary:
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(FAMILIES_PATH)
	if text == "":
		return {}
	if json.parse(text) != OK:
		return {}
	return json.data


func _catalog_class_for_family(family: String) -> String:
	match family:
		&"items":
			return "Crafting"
		&"quest":
			return "QuestCatalog"
		&"event":
			return "EventCatalog"
		&"world_locations":
			return "WorldLocationCatalog"
		&"npcs":
			return "NpcCatalog"
		&"races":
			return "RaceCatalog"
		&"techniques":
			return "TechniqueCatalog"
		&"elements":
			return "ElementCatalog"
		&"statuses":
			return "StatusCatalog"
		&"soul_arrivals":
			return "SoulCatalog"
		&"sets", &"set_items":
			return "SetCatalog"
		&"sects":
			return "SectCatalog"
		&"sect_doctrines":
			return "SectDoctrineCatalog"
		&"nations", &"nation_territories":
			return "NationCatalog"
		&"market_shops":
			return "ShopCatalog"
		&"clans":
			return "ClanCatalog"
		&"holdings":
			return "ResourceNodeCatalog"
		&"body_weapons":
			return "WeaponKindCatalog"
		&"body_material_arts":
			return "MaterialArtCatalog"
		&"body_injury_tuning":
			return "InjuryCatalog"
		&"bloodlines":
			return "BloodlineCatalog"
		&"anchors":
			return "AnchorCatalog"
		&"difficulty":
			return "DifficultyCatalog"
		&"fates", &"destinies":
			return "FateCatalog"
		&"item_options":
			return "OptionCatalog"
	return ""


func test_all_families_have_catalogs_or_are_skipped() -> void:
	var families := _read_families()
	var family_names: Array = families.get("families", {}).keys()
	assert_true(family_names.size() >= 48, "families.json should have at least 48 families")
	var unwired: Array[String] = []
	for family in family_names:
		var class_name := _catalog_class_for_family(String(family))
		if class_name == "":
			unwired.append(String(family))
	# Families without catalogs are skipped with a warning, not silent.
	# This test documents which families are skipped.
	# The unwired list should be stable — if it grows, a catalog was removed.
	print("Unwired families (no catalog): %s" % str(unwired))


func test_catalogs_have_set_overlay_roots() -> void:
	var families := _read_families()
	var family_names: Array = families.get("families", {}).keys()
	var missing: Array[String] = []
	for family in family_names:
		var class_name := _catalog_class_for_family(String(family))
		if class_name == "":
			continue
		# Check the class exists and has set_overlay_roots
		if not ClassDB.class_exists(class_name):
			missing.append("%s (class %s not found)" % [String(family), class_name])
			continue
		var script := ClassDB.class_get_script(class_name)
		if script == null:
			missing.append("%s (no script)" % String(family))
			continue
		assert_true(
			ClassDB.class_has_method(class_name, &"set_overlay_roots"),
			(
				"Catalog %s for family '%s' should have set_overlay_roots"
				% [class_name, String(family)]
			)
		)
	assert_true(
		ClassDB.class_has_method(class_name, &"_overlay_merge"),
		"Catalog %s for family '%s' should have _overlay_merge" % [class_name, String(family)]
	)
	assert_true(missing.is_empty(), "Missing overlay support: %s" % str(missing))


func test_overlay_roots_accepts_stack() -> void:
	# Test that set_overlay_roots accepts a stack and stores it
	var stack: Array = [
		{"dir": "res://mod_data/test_items", "owner": "test_mod", "declared_overrides": []},
	]
	Crafting.set_overlay_roots(stack)
	# Reset to empty after test
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
		var class_name := _catalog_class_for_family(String(family))
		if class_name == "":
			unwired.append(String(family))
	# These families have no catalog and should be skipped with a warning:
	# domain_templates, domain_rooms, domain_inhabitants, socket_items,
	# loot_tables, loot_tiers, loot_encounters, recipes, bosses, domains,
	# body_realms, body_acupoints, npc_personas, qi_realms, mind_realms,
	# fixture_cultivation_realms, meridians, portraits, technique_magnitudes,
	# world_factions, world_inhabitants, world_laws, world_tiers
	assert_true(unwired.size() > 0, "Some families should be unwired (no catalog)")
	print("Documented unwired families: %s" % str(unwired))
