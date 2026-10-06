class_name BuildingProjection
extends RefCounted

## Rebuilds an actor's building contribution from the ledger.
##
## **Derived, never stored.** The ledger is the only truth; this class is the
## one place that turns it into a summary component a pure provider reads.
##
## ## It grants NO stat. At all. This is the design, not an omission.
##
## ADR 0064: a clan hands out **recognition, never power**. Buildings grant
## infrastructure bonuses and unlock verbs, but never directly modify combat
## stats.

const SUMMARY_COMPONENT := BuildingSummary.COMPONENT


## The clan level derived from total building levels.
## clan_level = 1 + floor(total_building_levels / 3), max 5.
static func clan_level(ledger: Dictionary) -> int:
	var total := BuildingState.total_levels(ledger)
	return mini(5, 1 + total / 3)


## Whether the clan is overextended (total_building_levels > clan_level * 3).
static func is_overextended(ledger: Dictionary) -> bool:
	var total := BuildingState.total_levels(ledger)
	var level := clan_level(ledger)
	return total > level * 3


## The overextension penalty factor: 0.5 if overextended, 1.0 otherwise.
static func overextension_factor(ledger: Dictionary) -> float:
	return 0.5 if is_overextended(ledger) else 1.0


## The effective bonus value at a given level, accounting for overextension.
static func effective_bonus(ledger: Dictionary, building_id: StringName, level: int) -> float:
	var def := BuildingCatalog.instance().building_definition(building_id)
	if def == null:
		return 0.0
	var bonuses: Array[Dictionary] = def.bonuses_at(level)
	if bonuses.is_empty():
		return 0.0
	var total := 0.0
	for bonus in bonuses:
		total += float(bonus.get("value", 0.0))
	return total * overextension_factor(ledger)


## Project `ledger` onto `actor`. Attaches the summary component.
static func apply(actor: Actor, ledger: Dictionary) -> void:
	if actor == null:
		return
	var next := BuildingState.normalize(ledger)
	actor.set_module_data(BuildingState.MODULE_KEY, next)
	actor.set_component(SUMMARY_COMPONENT, BuildingSummary.from_ledger(next))


## Remove the building summary component from the actor.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	if actor.component(SUMMARY_COMPONENT) != null:
		actor.components.erase(SUMMARY_COMPONENT)
