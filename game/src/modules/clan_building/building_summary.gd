class_name BuildingSummary
extends RefCounted

## A derived summary of the building ledger, attached as a component so that
## BuildingProvider can read it purely (like ClanSummary does for clan).
##
## **Derived, never stored.** The ledger is the only truth.

const COMPONENT := &"building_summary"

var clan_level: int = 0
var is_overextended: bool = false
var overextension_factor: float = 1.0
var total_levels: int = 0
var upkeep_due: int = 0
var building_count: int = 0
var tech_count: int = 0


static func from_ledger(ledger: Dictionary) -> BuildingSummary:
	var summary := BuildingSummary.new()
	summary.clan_level = BuildingProjection.clan_level(ledger)
	summary.is_overextended = BuildingProjection.is_overextended(ledger)
	summary.overextension_factor = BuildingProjection.overextension_factor(ledger)
	summary.total_levels = BuildingState.total_levels(ledger)
	summary.tech_count = BuildingState.techs(ledger).size()
	var buildings := BuildingState.buildings(ledger)
	var upkeep := 0
	var count := 0
	for key in buildings.keys():
		var entry: Dictionary = buildings[key]
		var level := int(entry.get("level", 0))
		if level > 0:
			count += 1
			var def := BuildingCatalog.instance().building_definition(StringName(key))
			if def != null and bool(entry.get("active", false)):
				upkeep += def.upkeep_at(level)
	summary.building_count = count
	summary.upkeep_due = upkeep
	return summary
