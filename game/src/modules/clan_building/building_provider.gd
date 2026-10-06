class_name BuildingProvider
extends StatProvider

## Contributes the building module's own stat vocabulary from the actor's
## building summary component.
##
## ## Every id here is a bounded, non-combat SUMMARY.
##
## Buildings grant infrastructure and recognition, never combat power
## (ADR 0064). These numbers describe a clan's development level.
##
## **Pure, by construction.** Every value is read from the building summary
## component `BuildingProjection` attached — never from the catalog.


func contribute(context: StatContext) -> Dictionary:
	var summary := context.component(BuildingProjection.SUMMARY_COMPONENT) as BuildingSummary
	if summary == null:
		return {}
	return {
		BuildingStats.BUILDING_COUNT: float(summary.building_count),
		BuildingStats.BUILDING_LEVEL: float(summary.total_levels),
		BuildingStats.CLAN_LEVEL: float(summary.clan_level),
		BuildingStats.UPKEEP_DUE: float(summary.upkeep_due),
		BuildingStats.TECH_COUNT: float(summary.tech_count),
	}
