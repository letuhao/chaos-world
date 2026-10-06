extends TestCase

## Tests for the Clan Building system (ADR 0895).
##
## Buildings grant infrastructure and recognition, never combat power (ADR 0064).
## Yin-yang: every advantage carries its counterpart (upkeep, overextension, decay).

const HALL := &"hall_of_ancestors"
const TRAINING := &"training_grounds"
const STOREHOUSE := &"storehouse"
const MEDITATION := &"meditation_chamber"
const DEFENSIVE := &"defensive_works"


func setup() -> void:
	pass


func teardown() -> void:
	pass


func _born() -> Actor:
	var actor := (
		Actor
		. new(
			&"builder",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.WILL: 5.0,
				Stat.SPIRIT: 4.0,
				Stat.AGILITY: 6.0,
				Stat.COMPREHENSION: 3.0,
				Stat.APTITUDE: 3.0,
			}
		)
	)
	BuildingApi.attach(actor)
	return actor


# --- Construction ------------------------------------------------------------


func test_construct_building_succeeds() -> void:
	var actor := _born()
	var result := BuildingApi.construct(actor, HALL)
	assert_eq(result.get("ok", false), true, "construction should succeed")
	assert_eq(
		BuildingState.building_level(BuildingApi.building_state(actor), HALL), 1, "level is 1"
	)


func test_construct_unknown_building_fails() -> void:
	var actor := _born()
	var result := BuildingApi.construct(actor, &"nonexistent")
	assert_eq(result.get("ok", false), false, "unknown building should fail")


func test_construct_duplicate_fails() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var result := BuildingApi.construct(actor, HALL)
	assert_eq(result.get("ok", false), false, "duplicate construction should fail")


func test_upgrade_building_succeeds() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var result := BuildingApi.upgrade(actor, HALL)
	assert_eq(result.get("ok", false), true, "upgrade should succeed")
	assert_eq(
		BuildingState.building_level(BuildingApi.building_state(actor), HALL), 2, "level is 2"
	)


func test_upgrade_max_level_fails() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.upgrade(actor, HALL)
	BuildingApi.upgrade(actor, HALL)
	var result := BuildingApi.upgrade(actor, HALL)
	assert_eq(result.get("ok", false), false, "upgrade beyond max level should fail")


func test_demolish_building_succeeds() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var result := BuildingApi.demolish(actor, HALL)
	assert_eq(result, true, "demolish should succeed")
	assert_eq(
		BuildingState.building_level(BuildingApi.building_state(actor), HALL), 0, "level is 0"
	)


# --- Clan Level --------------------------------------------------------------


func test_clan_level_starts_at_1() -> void:
	var actor := _born()
	assert_eq(BuildingApi.clan_level(actor), 1, "clan level starts at 1")


func test_clan_level_increases_with_building_levels() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.construct(actor, TRAINING)
	BuildingApi.construct(actor, STOREHOUSE)
	assert_eq(BuildingApi.clan_level(actor), 2, "3 building levels = clan level 2")


func test_clan_level_caps_at_5() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.upgrade(actor, HALL)
	BuildingApi.upgrade(actor, HALL)
	BuildingApi.construct(actor, TRAINING)
	BuildingApi.upgrade(actor, TRAINING)
	BuildingApi.upgrade(actor, TRAINING)
	BuildingApi.construct(actor, STOREHOUSE)
	BuildingApi.upgrade(actor, STOREHOUSE)
	BuildingApi.upgrade(actor, STOREHOUSE)
	BuildingApi.construct(actor, MEDITATION)
	BuildingApi.upgrade(actor, MEDITATION)
	BuildingApi.upgrade(actor, MEDITATION)
	BuildingApi.construct(actor, DEFENSIVE)
	BuildingApi.upgrade(actor, DEFENSIVE)
	BuildingApi.upgrade(actor, DEFENSIVE)
	assert_eq(BuildingApi.clan_level(actor), 5, "clan level caps at 5")


# --- Upkeep ------------------------------------------------------------------


func test_pay_upkeep_returns_total() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.construct(actor, TRAINING)
	var upkeep := BuildingApi.pay_upkeep(actor)
	assert_eq(upkeep, 35, "upkeep = 15 + 20 = 35")


func test_upkeep_resets_days_unpaid() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var ledger := BuildingApi.building_state(actor)
	ledger = BuildingState.with_days_unpaid(ledger, HALL, 2)
	actor.set_module_data(BuildingState.MODULE_KEY, ledger)
	BuildingApi.pay_upkeep(actor)
	ledger = BuildingApi.building_state(actor)
	assert_eq(BuildingState.days_unpaid(ledger, HALL), 0, "upkeep resets days unpaid")


# --- Overextension -----------------------------------------------------------


func test_overextension_detection() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.construct(actor, TRAINING)
	BuildingApi.construct(actor, STOREHOUSE)
	BuildingApi.construct(actor, MEDITATION)
	assert_eq(
		BuildingProjection.is_overextended(BuildingApi.building_state(actor)),
		false,
		"not overextended"
	)
	BuildingApi.construct(actor, DEFENSIVE)
	assert_eq(
		BuildingProjection.is_overextended(BuildingApi.building_state(actor)),
		false,
		"still not overextended"
	)


func test_overextension_factor_halves_bonuses() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	BuildingApi.construct(actor, TRAINING)
	BuildingApi.construct(actor, STOREHOUSE)
	BuildingApi.construct(actor, MEDITATION)
	BuildingApi.construct(actor, DEFENSIVE)
	assert_eq(
		BuildingProjection.overextension_factor(BuildingApi.building_state(actor)),
		1.0,
		"factor is 1.0"
	)


# --- Building Summary --------------------------------------------------------


func test_building_summary_contains_all_fields() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var summary := BuildingApi.building_summary(actor)
	assert_eq(summary.get("has_actor", false), true, "has_actor is true")
	assert_eq(summary.get("clan_level", 0), 1, "clan_level is 1")
	assert_eq(summary.get("total_levels", 0), 1, "total_levels is 1")
	assert_eq(summary.get("buildings", {}).has(HALL), true, "buildings has HALL")
	var building: Dictionary = summary["buildings"][HALL]
	assert_eq(building.get("level", 0), 1, "building level is 1")
	assert_eq(building.get("active", false), true, "building is active")


# --- Tech Tree ---------------------------------------------------------------


func test_tech_tree_has_12_techs() -> void:
	var actor := _born()
	var tree := BuildingApi.tech_tree(actor)
	assert_eq(
		tree.get("available", []).size() + tree.get("locked", []).size(), 12, "12 techs total"
	)


func test_research_tech_succeeds() -> void:
	var actor := _born()
	var result := BuildingApi.research(actor, &"tech_01")
	assert_eq(result.get("ok", false), true, "research should succeed")
	assert_eq(
		BuildingState.has_tech(BuildingApi.building_state(actor), &"tech_01"),
		true,
		"tech is researched"
	)


func test_research_duplicate_tech_fails() -> void:
	var actor := _born()
	BuildingApi.research(actor, &"tech_01")
	var result := BuildingApi.research(actor, &"tech_01")
	assert_eq(result.get("ok", false), false, "duplicate research should fail")


# --- Gate Verbs --------------------------------------------------------------


func test_can_construct_gate() -> void:
	var actor := _born()
	var result := BuildingApi.can_construct(actor, HALL)
	assert_eq(result.get("ok", false), true, "can construct at start")


func test_clan_level_at_least_gate() -> void:
	var actor := _born()
	var gate := BuildingGate.evaluate(actor, {"verb": &"clan_level_at_least", "at": 1})
	assert_eq(gate.get("ok", false), true, "clan level 1 >= 1")
	gate = BuildingGate.evaluate(actor, {"verb": &"clan_level_at_least", "at": 2})
	assert_eq(gate.get("ok", false), false, "clan level 1 < 2")


# --- Building Def ------------------------------------------------------------


func test_building_def_costs_scale() -> void:
	var def := BuildingCatalog.instance().building_definition(HALL)
	assert_eq(def.material_cost(1), 150, "level 1 cost")
	assert_eq(def.material_cost(2), 300, "level 2 cost")
	assert_eq(def.material_cost(3), 600, "level 3 cost")


func test_building_def_upkeep_scales_with_level() -> void:
	var def := BuildingCatalog.instance().building_definition(HALL)
	assert_eq(def.upkeep_at(1), 15, "level 1 upkeep")
	assert_eq(def.upkeep_at(2), 30, "level 2 upkeep")
	assert_eq(def.upkeep_at(3), 45, "level 3 upkeep")


func test_building_def_construction_hours() -> void:
	var def := BuildingCatalog.instance().building_definition(HALL)
	assert_eq(def.construction_hours(1), 1, "level 1 hours")
	assert_eq(def.construction_hours(2), 2, "level 2 hours")
	assert_eq(def.construction_hours(3), 4, "level 3 hours")


func test_building_def_rank_discount() -> void:
	assert_eq(BuildingDef.rank_discount(&"head"), 0.25, "head discount")
	assert_eq(BuildingDef.rank_discount(&"heir"), 0.15, "heir discount")
	assert_eq(BuildingDef.rank_discount(&"core"), 0.10, "core discount")
	assert_eq(BuildingDef.rank_discount(&"inner"), 0.05, "inner discount")
	assert_eq(BuildingDef.rank_discount(&"outer"), 0.0, "outer discount")


# --- Building Catalog --------------------------------------------------------


func test_catalog_loads_all_buildings() -> void:
	var catalog := BuildingCatalog.instance()
	assert_eq(catalog.building_ids().size(), 5, "5 buildings loaded")


func test_catalog_building_categories() -> void:
	var catalog := BuildingCatalog.instance()
	assert_eq(catalog.building_definition(HALL).category, &"lineage", "hall category")
	assert_eq(catalog.building_definition(TRAINING).category, &"combat", "training category")
	assert_eq(catalog.building_definition(STOREHOUSE).category, &"economy", "storehouse category")
	assert_eq(
		catalog.building_definition(MEDITATION).category, &"cultivation", "meditation category"
	)
	assert_eq(catalog.building_definition(DEFENSIVE).category, &"military", "defensive category")


# --- Building Stats ----------------------------------------------------------


func test_building_stats_are_non_combat() -> void:
	var stats := [
		BuildingStats.BUILDING_COUNT,
		BuildingStats.BUILDING_LEVEL,
		BuildingStats.CLAN_LEVEL,
		BuildingStats.UPKEEP_DUE,
		BuildingStats.TECH_COUNT,
	]
	for stat_id in stats:
		assert_eq(stat_id.begins_with("attack_"), false, "'%s' is not a combat id" % stat_id)
		assert_eq(stat_id.begins_with("defense_"), false, "'%s' is not a combat id" % stat_id)


# --- Building State ----------------------------------------------------------


func test_building_state_normalize_empty() -> void:
	var ledger := BuildingState.normalize({})
	assert_eq(ledger.get("version", 0), 1, "version is 1")
	assert_eq(ledger.get("buildings", {}).size(), 0, "no buildings")


func test_building_state_with_building_level() -> void:
	var ledger := BuildingState.empty()
	ledger = BuildingState.with_building_level(ledger, HALL, 2)
	assert_eq(BuildingState.building_level(ledger, HALL), 2, "level is 2")
	assert_eq(BuildingState.total_levels(ledger), 2, "total levels is 2")


func test_building_state_with_decay() -> void:
	var ledger := BuildingState.empty()
	ledger = BuildingState.with_building_level(ledger, HALL, 2)
	ledger = BuildingState.with_days_unpaid(ledger, HALL, 30)
	ledger = BuildingState.with_decay(ledger)
	assert_eq(BuildingState.building_level(ledger, HALL), 1, "decay reduces level by 1")


func test_building_state_with_tech() -> void:
	var ledger := BuildingState.empty()
	ledger = BuildingState.with_tech(ledger, &"tech_01")
	assert_eq(BuildingState.has_tech(ledger, &"tech_01"), true, "tech is researched")
	assert_eq(BuildingState.techs(ledger).size(), 1, "1 tech researched")


# --- Building Provider -------------------------------------------------------


func test_building_provider_contributes_non_combat_stats() -> void:
	var actor := _born()
	BuildingApi.construct(actor, HALL)
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	var values := BuildingProvider.new().contribute(context)
	assert_eq(values.has(BuildingStats.BUILDING_COUNT), true, "has BUILDING_COUNT")
	assert_eq(values.has(BuildingStats.CLAN_LEVEL), true, "has CLAN_LEVEL")
	assert_eq(values.has(&"attack_physical"), false, "no combat id is contributed")


# --- Building Projection -----------------------------------------------------


func test_building_projection_clan_level() -> void:
	var ledger := BuildingState.empty()
	ledger = BuildingState.with_building_level(ledger, HALL, 1)
	ledger = BuildingState.with_building_level(ledger, TRAINING, 1)
	ledger = BuildingState.with_building_level(ledger, STOREHOUSE, 1)
	assert_eq(BuildingProjection.clan_level(ledger), 2, "clan level is 2")


func test_building_projection_overextension() -> void:
	var ledger := BuildingState.empty()
	ledger = BuildingState.with_building_level(ledger, HALL, 3)
	ledger = BuildingState.with_building_level(ledger, TRAINING, 3)
	ledger = BuildingState.with_building_level(ledger, STOREHOUSE, 3)
	assert_eq(BuildingProjection.is_overextended(ledger), false, "not overextended")
	ledger = BuildingState.with_building_level(ledger, MEDITATION, 3)
	assert_eq(BuildingProjection.is_overextended(ledger), false, "still not overextended")
	ledger = BuildingState.with_building_level(ledger, DEFENSIVE, 3)
	assert_eq(BuildingProjection.is_overextended(ledger), false, "still not overextended")
