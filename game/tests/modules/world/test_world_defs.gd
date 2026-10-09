extends TestCase

## ADR 0008: boss and domain content defs load and cross-reference.
## ADR 0019/0045/0046/0047: world resource defs load with expected fields.


func test_boss_def_loads() -> void:
	var boss := load("res://data/bosses/flame_dragon.tres")
	assert_eq(boss is BossDef, true, "loads BossDef")
	assert_eq(boss.domain_id, &"flame_valley", "domain")
	# The legacy flat `loot` array is the migration path and is empty across the whole
	# shipped corpus: what this boss drops is bound on `LootTier.boss_tables` instead
	# (ADR 0033). Asserting the migration field would pin the test to content that has
	# since been migrated, which is how this line came to be wrong.
	assert_eq(boss.loot.is_empty(), true, "the migration loot array is left to the loot module")


func test_domain_def_loads() -> void:
	var domain := load("res://data/domains/flame_valley.tres")
	assert_eq(domain is DomainDef, true, "loads DomainDef")
	assert_eq(domain.boss_ids.has(&"flame_dragon"), true, "boss")


# ── WorldTierDef ─────────────────────────────────────────────────────────────


func test_tier_mortal_world_loads() -> void:
	var tier := load("res://data/world/tiers/mortal_world.tres")
	assert_eq(tier is WorldTierDef, true, "loads WorldTierDef")
	assert_eq(tier.tier_id, &"mortal_world", "tier_id")
	assert_eq(L.t(tier.display_name), "Mortal World", "display_name")
	assert_eq(tier.realm_min, 1, "realm_min")
	assert_eq(tier.realm_max, 9, "realm_max")
	assert_eq(tier.law_slots, 3, "law_slots")
	assert_eq(tier.available_life_forms.size(), 2, "life_forms count")
	assert_eq(tier.available_life_forms.has(&"plant"), true, "has plant")
	assert_eq(tier.available_life_forms.has(&"beast"), true, "has beast")
	assert_eq(tier.upkeep_rate_min, 0.1, "upkeep_rate_min")
	assert_eq(tier.upkeep_rate_max, 0.5, "upkeep_rate_max")
	assert_eq(tier.time_flow_min, 0.5, "time_flow_min")
	assert_eq(tier.time_flow_max, 2.0, "time_flow_max")
	assert_eq(tier.size_min, 10.0, "size_min")
	assert_eq(tier.size_max, 100.0, "size_max")


func test_tier_spirit_world_loads() -> void:
	var tier := load("res://data/world/tiers/spirit_world.tres")
	assert_eq(tier is WorldTierDef, true, "loads WorldTierDef")
	assert_eq(tier.tier_id, &"spirit_world", "tier_id")
	assert_eq(L.t(tier.display_name), "Spirit World", "display_name")
	assert_eq(tier.realm_min, 10, "realm_min")
	assert_eq(tier.realm_max, 18, "realm_max")
	assert_eq(tier.law_slots, 6, "law_slots")
	assert_eq(tier.available_life_forms.size(), 3, "life_forms count")
	assert_eq(tier.available_life_forms.has(&"humanoid"), true, "has humanoid")
	assert_eq(tier.upkeep_rate_min, 0.5, "upkeep_rate_min")
	assert_eq(tier.upkeep_rate_max, 1.0, "upkeep_rate_max")
	assert_eq(tier.time_flow_min, 1.0, "time_flow_min")
	assert_eq(tier.time_flow_max, 10.0, "time_flow_max")
	assert_eq(tier.size_min, 100.0, "size_min")
	assert_eq(tier.size_max, 1000.0, "size_max")


func test_tier_immortal_world_loads() -> void:
	var tier := load("res://data/world/tiers/immortal_world.tres")
	assert_eq(tier is WorldTierDef, true, "loads WorldTierDef")
	assert_eq(tier.tier_id, &"immortal_world", "tier_id")
	assert_eq(L.t(tier.display_name), "Immortal World", "display_name")
	assert_eq(tier.realm_min, 19, "realm_min")
	assert_eq(tier.realm_max, 27, "realm_max")
	assert_eq(tier.law_slots, 10, "law_slots")
	assert_eq(tier.available_life_forms.size(), 4, "life_forms count")
	assert_eq(tier.available_life_forms.has(&"elemental"), true, "has elemental")
	assert_eq(tier.upkeep_rate_min, 1.0, "upkeep_rate_min")
	assert_eq(tier.upkeep_rate_max, 5.0, "upkeep_rate_max")
	assert_eq(tier.time_flow_min, 5.0, "time_flow_min")
	assert_eq(tier.time_flow_max, 50.0, "time_flow_max")
	assert_eq(tier.size_min, 1000.0, "size_min")
	assert_eq(tier.size_max, 10000.0, "size_max")


func test_tier_transcendent_world_loads() -> void:
	var tier := load("res://data/world/tiers/transcendent_world.tres")
	assert_eq(tier is WorldTierDef, true, "loads WorldTierDef")
	assert_eq(tier.tier_id, &"transcendent_world", "tier_id")
	assert_eq(L.t(tier.display_name), "Transcendent World", "display_name")
	assert_eq(tier.realm_min, 28, "realm_min")
	assert_eq(tier.realm_max, 30, "realm_max")
	assert_eq(tier.law_slots, 15, "law_slots")
	assert_eq(tier.available_life_forms.size(), 4, "life_forms count")
	assert_eq(tier.upkeep_rate_min, 5.0, "upkeep_rate_min")
	assert_eq(tier.upkeep_rate_max, 20.0, "upkeep_rate_max")
	assert_eq(tier.time_flow_min, 10.0, "time_flow_min")
	assert_eq(tier.time_flow_max, 100.0, "time_flow_max")
	assert_eq(tier.size_min, 10000.0, "size_min")
	assert_eq(tier.size_max, 100000.0, "size_max")


# ── WorldLawDef ──────────────────────────────────────────────────────────────


func test_law_spatial_loads() -> void:
	var law := load("res://data/world/laws/spatial_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"spatial_law", "law_id")
	assert_eq(L.t(law.display_name), "Spatial Law", "display_name")
	assert_eq(law.group, &"spatial", "group")
	assert_eq(law.value_min, 0.1, "value_min")
	assert_eq(law.value_max, 10.0, "value_max")
	assert_eq(
		L.t(law.description),
		"Governs world size, dimensions, and spatial stability.",
		"description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")
	assert_eq(law.tier_ids.has(&"mortal_world"), true, "has mortal_world")


func test_law_temporal_loads() -> void:
	var law := load("res://data/world/laws/temporal_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"temporal_law", "law_id")
	assert_eq(L.t(law.display_name), "Temporal Law", "display_name")
	assert_eq(law.group, &"temporal", "group")
	assert_eq(law.value_min, 0.1, "value_min")
	assert_eq(law.value_max, 100.0, "value_max")
	assert_eq(
		L.t(law.description),
		"Governs time flow rate and temporal stability within the world.",
		"description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")


func test_law_elemental_loads() -> void:
	var law := load("res://data/world/laws/elemental_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"elemental_law", "law_id")
	assert_eq(L.t(law.display_name), "Elemental Law", "display_name")
	assert_eq(law.group, &"elemental", "group")
	assert_eq(law.value_min, 0.0, "value_min")
	assert_eq(law.value_max, 1.0, "value_max")
	assert_eq(
		L.t(law.description),
		"Governs dominant elements, elemental balance, and seasonal cycles.",
		"description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")


func test_law_physical_loads() -> void:
	var law := load("res://data/world/laws/physical_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"physical_law", "law_id")
	assert_eq(L.t(law.display_name), "Physical Law", "display_name")
	assert_eq(law.group, &"physical", "group")
	assert_eq(law.value_min, 0.1, "value_min")
	assert_eq(law.value_max, 10.0, "value_max")
	assert_eq(
		L.t(law.description),
		"Governs gravity, energy density, and material hardness.",
		"description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")


func test_law_life_loads() -> void:
	var law := load("res://data/world/laws/life_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"life_law", "law_id")
	assert_eq(L.t(law.display_name), "Life Law", "display_name")
	assert_eq(law.group, &"life", "group")
	assert_eq(law.value_min, 0.0, "value_min")
	assert_eq(law.value_max, 1.0, "value_max")
	assert_eq(
		L.t(law.description),
		"Governs allowed life forms, evolution speed, and intelligence ceiling.",
		"description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")


func test_law_qi_loads() -> void:
	var law := load("res://data/world/laws/qi_law.tres")
	assert_eq(law is WorldLawDef, true, "loads WorldLawDef")
	assert_eq(law.law_id, &"qi_law", "law_id")
	assert_eq(L.t(law.display_name), "Qi Law", "display_name")
	assert_eq(law.group, &"qi", "group")
	assert_eq(law.value_min, 0.1, "value_min")
	assert_eq(law.value_max, 100.0, "value_max")
	assert_eq(
		L.t(law.description), "Governs qi density, qi type, and qi tide cycles.", "description"
	)
	assert_eq(law.tier_ids.size(), 4, "tier_ids count")


# ── WorldFactionDef ─────────────────────────────────────────────────────────


func test_faction_qi_dao_loads() -> void:
	var faction := load("res://data/world/factions/qi_dao.tres")
	assert_eq(faction is WorldFactionDef, true, "loads WorldFactionDef")
	assert_eq(faction.faction_id, &"qi_dao", "faction_id")
	assert_eq(L.t(faction.display_name), "Qi Dao", "display_name")
	assert_eq(faction.dao_alignment, &"qi", "dao_alignment")
	assert_eq(faction.home_tier, &"spirit_world", "home_tier")
	assert_eq(
		faction.philosophy,
		"Creation through energy. The universe is qi in motion; to shape qi is to shape reality.",
		"philosophy"
	)
	assert_eq(faction.relationships.size(), 2, "relationships count")


func test_faction_body_dao_loads() -> void:
	var faction := load("res://data/world/factions/body_dao.tres")
	assert_eq(faction is WorldFactionDef, true, "loads WorldFactionDef")
	assert_eq(faction.faction_id, &"body_dao", "faction_id")
	assert_eq(L.t(faction.display_name), "Body Dao", "display_name")
	assert_eq(faction.dao_alignment, &"body", "dao_alignment")
	assert_eq(faction.home_tier, &"mortal_world", "home_tier")
	assert_eq(
		faction.philosophy,
		(
			"Preservation through form. The body is the foundation of all cultivation; "
			+ "a perfect form endures beyond worlds."
		),
		"philosophy"
	)
	assert_eq(faction.relationships.size(), 2, "relationships count")


func test_faction_mind_dao_loads() -> void:
	var faction := load("res://data/world/factions/mind_dao.tres")
	assert_eq(faction is WorldFactionDef, true, "loads WorldFactionDef")
	assert_eq(faction.faction_id, &"mind_dao", "faction_id")
	assert_eq(L.t(faction.display_name), "Mind Dao", "display_name")
	assert_eq(faction.dao_alignment, &"mind", "dao_alignment")
	assert_eq(faction.home_tier, &"transcendent_world", "home_tier")
	assert_eq(
		faction.philosophy,
		(
			"Transcendence through spirit. The mind is the seed of the Dao; "
			+ "to refine the self is to touch the infinite."
		),
		"philosophy"
	)
	assert_eq(faction.relationships.size(), 2, "relationships count")


# ── WorldLocationDef ────────────────────────────────────────────────────────


func test_location_mortal_plains_loads() -> void:
	var loc := load("res://data/world/locations/mortal_plains.tres")
	assert_eq(loc is WorldLocationDef, true, "loads WorldLocationDef")
	assert_eq(loc.location_id, &"mortal_plains", "location_id")
	assert_eq(L.t(loc.display_name), "Mortal Plains", "display_name")
	assert_eq(loc.tier, &"mortal_world", "tier")
	assert_eq(loc.faction_id, &"body_dao", "faction_id")
	assert_eq(loc.resources.size(), 2, "resources count")
	assert_eq(loc.resources.has(&"iron_ore"), true, "has iron_ore")
	assert_eq(loc.resources.has(&"herb_common"), true, "has herb_common")
	assert_eq(loc.inhabitant_types.size(), 2, "inhabitant_types count")
	assert_eq(loc.inhabitant_types.has(&"beast"), true, "has beast")
	# The quest board joined the plains with the quest lane's spawn markers; the pin
	# moved with the data rather than the data being trimmed to the pin.
	assert_eq(loc.inhabitant_types.has(&"quest_board"), true, "has quest_board")
	assert_eq(loc.danger_level, 2, "danger_level")


func test_location_spirit_peaks_loads() -> void:
	var loc := load("res://data/world/locations/spirit_peaks.tres")
	assert_eq(loc is WorldLocationDef, true, "loads WorldLocationDef")
	assert_eq(loc.location_id, &"spirit_peaks", "location_id")
	assert_eq(L.t(loc.display_name), "Spirit Peaks", "display_name")
	assert_eq(loc.tier, &"spirit_world", "tier")
	assert_eq(loc.faction_id, &"qi_dao", "faction_id")
	assert_eq(loc.resources.size(), 2, "resources count")
	assert_eq(loc.resources.has(&"spirit_stone"), true, "has spirit_stone")
	assert_eq(loc.resources.has(&"jade_ore"), true, "has jade_ore")
	assert_eq(loc.inhabitant_types.size(), 2, "inhabitant_types count")
	assert_eq(loc.inhabitant_types.has(&"humanoid"), true, "has humanoid")
	assert_eq(loc.danger_level, 5, "danger_level")


func test_location_immortal_court_loads() -> void:
	var loc := load("res://data/world/locations/immortal_court.tres")
	assert_eq(loc is WorldLocationDef, true, "loads WorldLocationDef")
	assert_eq(loc.location_id, &"immortal_court", "location_id")
	assert_eq(L.t(loc.display_name), "Immortal Court", "display_name")
	assert_eq(loc.tier, &"immortal_world", "tier")
	assert_eq(loc.faction_id, &"mind_dao", "faction_id")
	assert_eq(loc.resources.size(), 2, "resources count")
	assert_eq(loc.resources.has(&"immortal_essence"), true, "has immortal_essence")
	assert_eq(loc.resources.has(&"star_metal"), true, "has star_metal")
	assert_eq(loc.inhabitant_types.size(), 2, "inhabitant_types count")
	assert_eq(loc.inhabitant_types.has(&"elemental"), true, "has elemental")
	assert_eq(loc.danger_level, 8, "danger_level")


func test_location_transcendent_realm_loads() -> void:
	var loc := load("res://data/world/locations/transcendent_realm.tres")
	assert_eq(loc is WorldLocationDef, true, "loads WorldLocationDef")
	assert_eq(loc.location_id, &"transcendent_realm", "location_id")
	assert_eq(L.t(loc.display_name), "Transcendent Realm", "display_name")
	assert_eq(loc.tier, &"transcendent_world", "tier")
	assert_eq(loc.faction_id, &"mind_dao", "faction_id")
	assert_eq(loc.resources.size(), 2, "resources count")
	assert_eq(loc.resources.has(&"dao_fragment"), true, "has dao_fragment")
	assert_eq(loc.resources.has(&"void_crystal"), true, "has void_crystal")
	assert_eq(loc.inhabitant_types.size(), 2, "inhabitant_types count")
	assert_eq(loc.danger_level, 10, "danger_level")


# ── WorldInhabitantDef ──────────────────────────────────────────────────────


func test_inhabitant_spirit_herb_loads() -> void:
	var inh := load("res://data/world/inhabitants/spirit_herb.tres")
	assert_eq(inh is WorldInhabitantDef, true, "loads WorldInhabitantDef")
	assert_eq(inh.inhabitant_id, &"spirit_herb", "inhabitant_id")
	assert_eq(L.t(inh.display_name), "Spirit Herb", "display_name")
	assert_eq(inh.type, &"plant", "type")
	assert_eq(inh.tier_ids.size(), 4, "tier_ids count")
	assert_eq(inh.tier_ids.has(&"mortal_world"), true, "has mortal_world")
	assert_eq(inh.loyalty_min, 0.0, "loyalty_min")
	assert_eq(inh.loyalty_max, 0.3, "loyalty_max")
	assert_eq(inh.combat_power_min, 0.0, "combat_power_min")
	assert_eq(inh.combat_power_max, 1.0, "combat_power_max")


func test_inhabitant_ironhide_bear_loads() -> void:
	var inh := load("res://data/world/inhabitants/ironhide_bear.tres")
	assert_eq(inh is WorldInhabitantDef, true, "loads WorldInhabitantDef")
	assert_eq(inh.inhabitant_id, &"ironhide_bear", "inhabitant_id")
	assert_eq(L.t(inh.display_name), "Ironhide Bear", "display_name")
	assert_eq(inh.type, &"beast", "type")
	assert_eq(inh.tier_ids.size(), 3, "tier_ids count")
	assert_eq(inh.tier_ids.has(&"mortal_world"), true, "has mortal_world")
	assert_eq(inh.loyalty_min, 0.1, "loyalty_min")
	assert_eq(inh.loyalty_max, 0.6, "loyalty_max")
	assert_eq(inh.combat_power_min, 5.0, "combat_power_min")
	assert_eq(inh.combat_power_max, 50.0, "combat_power_max")


func test_inhabitant_azure_disciple_loads() -> void:
	var inh := load("res://data/world/inhabitants/azure_disciple.tres")
	assert_eq(inh is WorldInhabitantDef, true, "loads WorldInhabitantDef")
	assert_eq(inh.inhabitant_id, &"azure_disciple", "inhabitant_id")
	assert_eq(L.t(inh.display_name), "Azure Disciple", "display_name")
	assert_eq(inh.type, &"humanoid", "type")
	assert_eq(inh.tier_ids.size(), 3, "tier_ids count")
	assert_eq(inh.tier_ids.has(&"spirit_world"), true, "has spirit_world")
	assert_eq(inh.loyalty_min, 0.3, "loyalty_min")
	assert_eq(inh.loyalty_max, 0.9, "loyalty_max")
	assert_eq(inh.combat_power_min, 20.0, "combat_power_min")
	assert_eq(inh.combat_power_max, 200.0, "combat_power_max")


func test_inhabitant_storm_elemental_loads() -> void:
	var inh := load("res://data/world/inhabitants/storm_elemental.tres")
	assert_eq(inh is WorldInhabitantDef, true, "loads WorldInhabitantDef")
	assert_eq(inh.inhabitant_id, &"storm_elemental", "inhabitant_id")
	assert_eq(L.t(inh.display_name), "Storm Elemental", "display_name")
	assert_eq(inh.type, &"elemental", "type")
	assert_eq(inh.tier_ids.size(), 2, "tier_ids count")
	assert_eq(inh.tier_ids.has(&"immortal_world"), true, "has immortal_world")
	assert_eq(inh.loyalty_min, 0.0, "loyalty_min")
	assert_eq(inh.loyalty_max, 0.5, "loyalty_max")
	assert_eq(inh.combat_power_min, 100.0, "combat_power_min")
	assert_eq(inh.combat_power_max, 1000.0, "combat_power_max")


# ── the catalogs cross-reference each other ──────────────────────────────────
## Every authored family cross-references WITHIN the shipped catalogs: a location's
## faction and tier resolve, and a faction's `relationships` name only factions that
## ship. The three faction files carried relationship rows no reader ever checked
## (BL-0227); this is the gate that turns them from prose into content.
func test_world_catalogs_cross_reference() -> void:
	var faction_ids := WorldDefIndex.ids(&"faction")
	var tier_ids := WorldDefIndex.ids(&"tier")
	assert_eq(faction_ids.size() >= 3, true, "the dao factions ship")
	assert_eq(tier_ids.size() >= 3, true, "the world tiers ship")
	for faction_id in faction_ids:
		var faction := WorldDefIndex.definition(&"faction", faction_id) as WorldFactionDef
		assert_ne(faction, null, "faction %s loads through the index" % String(faction_id))
		for relation in faction.relationships:
			var row := relation as Dictionary
			assert_eq(
				faction_ids.has(StringName(row.get("faction_id", ""))),
				true,
				"%s relates to a shipped faction" % String(faction_id)
			)
	var catalog := WorldLocationCatalog.instance()
	for location_id in catalog.location_ids():
		var location := catalog.definition(location_id)
		assert_ne(location, null, "location %s loads" % String(location_id))
		assert_eq(
			faction_ids.has(location.faction_id),
			true,
			"location %s names a shipped faction" % String(location_id)
		)
		assert_eq(
			tier_ids.has(location.tier),
			true,
			"location %s names a shipped tier" % String(location_id)
		)


# ── the legacy domain records are the id catalog, and it is ONE universe ─────

const DOMAIN_DIR := "res://data/domains"
const BOSS_DIR := "res://data/bosses"
const ENCOUNTER_DIR := "res://data/loot/encounters"


## BL-0474's decision in executable form. The 160 legacy `DomainDef` records are the
## domain-id catalog the corpus keys on: bosses name one via `domain_id`, authored
## encounters carry one, items declare one in `sources` (gated by
## `tests/acquisition/test_domain_route_acquisition.gd`, which resolves them against
## the encounters), and a record's own `boss_ids` lists exactly the bosses that name
## it. Measured 2026-10-09: bosses, encounters and items are all the SAME 160 ids as
## the records. So they are not orphaned and are not deleted; they are not maps, so
## they are not migrated into templates; they are the registry, and this test keeps
## the three text sides from drifting apart silently — one renamed side would orphan
## content while every suite stayed green, which is the shape the audit named.
func test_the_domain_records_are_the_id_catalog_the_corpus_agrees_on() -> void:
	var records := _domain_records()
	var defs: Array[String] = []
	defs.assign(records.keys())
	defs.sort()
	assert_eq(defs.size() >= 160, true, "the registry still ships (%d records)" % defs.size())
	var naming := _bosses_by_domain()
	var boss_refs: Array[String] = []
	boss_refs.assign(naming.keys())
	boss_refs.sort()
	assert_eq(
		_set_diff(defs, naming).is_empty(),
		true,
		(
			"every record is named by a boss; unnamed: %s"
			% ", ".join(_set_diff(defs, naming).slice(0, 8))
		)
	)
	assert_eq(
		_set_diff(boss_refs, records).is_empty(),
		true,
		(
			"every boss names a shipped record; naming nothing: %s"
			% ", ".join(_set_diff(boss_refs, records).slice(0, 8))
		)
	)
	var encounters := _encounter_domain_refs()
	assert_eq(
		_set_diff(defs, encounters).is_empty(),
		true,
		(
			"every record is hosted by an encounter; unhosted: %s"
			% ", ".join(_set_diff(defs, encounters).slice(0, 8))
		)
	)
	assert_eq(
		_set_diff(encounters, records).is_empty(),
		true,
		(
			"every encounter hosts a shipped record; hosting nothing: %s"
			% ", ".join(_set_diff(encounters, records).slice(0, 8))
		)
	)
	var drifted: Array[String] = []
	for domain_id in defs:
		var listed: Array[String] = (records[domain_id] as Array[String]).duplicate()
		listed.sort()
		var actual: Array[String] = (naming.get(domain_id, []) as Array[String]).duplicate()
		actual.sort()
		if listed != actual:
			drifted.append(domain_id)
	assert_eq(
		drifted.is_empty(),
		true,
		(
			"each record's boss_ids matches the bosses that name it; drifted: %s"
			% ", ".join(drifted.slice(0, 8))
		)
	)


## `left`'s members absent from `right`, sorted — the set difference a failure message
## needs, because two 160-entry arrays do not name their own disagreement. `right` may
## be the keyed map or a plain sorted list, so both shapes read the same way.
func _set_diff(left: Array[String], right: Variant) -> Array[String]:
	var known := {}
	if right is Dictionary:
		for key in (right as Dictionary).keys():
			known[String(key)] = true
	else:
		for value in right as Array:
			known[String(value)] = true
	var out: Array[String] = []
	for value in left:
		if not known.has(value):
			out.append(value)
	out.sort()
	return out


## `{record id: the boss ids the record's own boss_ids lists}`, one pass over the
## registry so the walk is 160 file reads whether the corpus holds 2 domains or 200.
func _domain_records() -> Dictionary:
	var out := {}
	for path in ContentScan.files_under(DOMAIN_DIR):
		var text := _main_block(FileAccess.get_file_as_string(path))
		var id := _scalar_id(text)
		if id != "":
			out[id] = _all_quoted_in_array(text, "boss_ids")
	return out


## `{domain id: the boss ids whose own domain_id names it}`, one pass over the boss
## corpus. The reverse walk: content asks the boss who it serves; only the record
## claims who serves it, and the two must agree.
func _bosses_by_domain() -> Dictionary:
	var out := {}
	for path in ContentScan.files_under(BOSS_DIR):
		var text := _main_block(FileAccess.get_file_as_string(path))
		var domain_id := _scalar_domain_id(text)
		var boss_id := _scalar_id(text)
		if domain_id == "" or boss_id == "":
			continue
		# An explicit branch, not `out.get(id, [])`: the literal default is an UNTYPED
		# array, and assigning it to `Array[String]` aborts the whole walk at runtime —
		# the failure that made this map answer `{}` while the probe beside it read a
		# boss correctly.
		var row: Array[String] = []
		if out.has(domain_id):
			row = out[domain_id]
		row.append(boss_id)
		out[domain_id] = row
	return out


## Every `domain_id` an authored encounter carries, as a sorted id list.
func _encounter_domain_refs() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(ENCOUNTER_DIR):
		var ref := _scalar_domain_id(_main_block(FileAccess.get_file_as_string(path)))
		if ref != "":
			out.append(ref)
	out.sort()
	return out


## The file's own `[resource]` block, excluding every `sub_resource` above it. A boss
## authors `LootTier`/gate sub-resources that carry their OWN `domain_id`, so a
## first-match scan reads the wrong block and reports a drift that is not there.
func _main_block(text: String) -> String:
	var marker := "\n[resource]"
	var index := text.rfind(marker)
	return text.substr(index + 1) if index >= 0 else text


func _scalar_id(text: String) -> String:
	var re := RegEx.create_from_string('(?m)^id = &"([^"]+)"')
	var found := re.search(text)
	return found.get_string(1) if found != null else ""


func _scalar_domain_id(text: String) -> String:
	var re := RegEx.create_from_string('(?m)^domain_id = &"([^"]+)"')
	var found := re.search(text)
	return found.get_string(1) if found != null else ""


func _all_quoted_in_array(text: String, field: String) -> Array[String]:
	var block := RegEx.create_from_string(
		"(?ms)^%s = Array\\[StringName\\]\\(\\[(.*?)\\]\\)" % field
	)
	var found := block.search(text)
	if found == null:
		return []
	var out: Array[String] = []
	for item in RegEx.create_from_string('&"([^"]+)"').search_all(found.get_string(1)):
		out.append(item.get_string(1))
	return out
