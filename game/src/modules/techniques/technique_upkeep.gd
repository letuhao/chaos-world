class_name TechniqueUpkeep
extends RefCounted

## Which equipped techniques are currently paying their upkeep (ADR 0054).
##
## This is the same generic shape as `EquipmentUpkeep`, welded to a different slot
## list rather than a fork of it. `EquipmentUpkeep` is bound to `Equipment.SLOTS`,
## so a technique slot needs its own settle loop that shares the same `_pay`.
##
## Upkeep is an ongoing obligation, not an equip gate, so this never unequips
## anything and never blocks an equip. A technique that cannot pay is SUSPENDED: it
## stays equipped and contributes nothing. That ordering is deliberate — if spending
## in combat could unequip, a fight you were winning would strip you mid-fight, and
## a player could never opt out of an upkeep they could not afford.

## technique_id -> true when suspended. Absent means active.
var _suspended: Dictionary = {}


func is_suspended(technique_id: StringName) -> bool:
	return _suspended.get(technique_id, false)


func suspended() -> Array[StringName]:
	var out: Array[StringName] = []
	for technique_id in _suspended.keys():
		out.append(technique_id)
	return out


func clear() -> void:
	_suspended.clear()


## Drop the suspension record for a technique that is no longer equipped, so a
## technique that is unequipped and later re-equipped starts paying again rather
## than inheriting a stale refusal.
func forget(technique_id: StringName) -> void:
	_suspended.erase(technique_id)


## Settle one interval for every equipped technique that declares upkeep. Returns
## the technique ids that changed state, so a caller rebuilds only those. Suspension
## is per technique and keyed by id, so paying one technique's upkeep does not
## reactivate another's.
func settle(actor: Actor, equipped: Array[StringName]) -> Array[StringName]:
	var changed: Array[StringName] = []
	if actor == null:
		return changed
	for technique_id in equipped:
		var def := TechniqueCatalog.instance().definition(technique_id)
		if def == null or def.upkeep.is_empty():
			continue
		var was := is_suspended(technique_id)
		var paid := _pay(actor, def)
		if paid and was:
			_suspended.erase(technique_id)
			changed.append(technique_id)
		elif not paid and not was:
			_suspended[technique_id] = true
			changed.append(technique_id)
	return changed


## Pay one interval, or refuse. Base pools only, so a technique cannot fund its own
## upkeep out of the stats it grants — the same rule equipment follows, and the one
## that keeps `ItemRequirement`'s reserve load-bearing: without a reserve, upkeep
## would chip an actor to zero and suspend on the last tick.
func _pay(actor: Actor, def: TechniqueDef) -> bool:
	for resource_id in def.upkeep.keys():
		var pool := actor.resource(StringName(resource_id))
		if pool == null:
			return false
		var reserve := 0.0
		if def.requirement != null:
			reserve = float(def.requirement.upkeep_reserve.get(resource_id, 0.0))
		if pool.current - float(def.upkeep[resource_id]) < reserve:
			return false
	for resource_id in def.upkeep.keys():
		var pool: ResourcePool = actor.resource(StringName(resource_id))
		pool.current -= float(def.upkeep[resource_id])
	return true
