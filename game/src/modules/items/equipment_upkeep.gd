class_name EquipmentUpkeep
extends RefCounted

## Tracks which equipped items are currently paying their upkeep (ADR 0052).
##
## Upkeep is an ongoing obligation rather than an equip gate, so this never unequips
## anything and never blocks an equip. An item that cannot pay is SUSPENDED: it stays
## equipped and contributes nothing. That ordering is deliberate — if spending in
## combat could unequip gear, a fight you were winning would strip you mid-fight, and
## a player could never opt out of an upkeep they could not afford.
##
## Suspension is per item and keyed by slot, so paying one item's upkeep does not
## reactivate another's.

## slot -> true when suspended. Absent means active.
var _suspended: Dictionary = {}


func is_suspended(slot: StringName) -> bool:
	return _suspended.get(slot, false)


func suspended_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in _suspended:
		out.append(slot)
	return out


func clear() -> void:
	_suspended.clear()


## Settle one interval for every equipped slot that declares upkeep. Returns the slots
## that changed state, so a caller can rebuild only those.
func settle(actor: Actor, equipment: Equipment) -> Array[StringName]:
	var changed: Array[StringName] = []
	if actor == null or equipment == null:
		return changed
	for slot in Equipment.SLOTS:
		var def := equipment.definition(slot)
		if def == null or def.requirement == null or def.requirement.upkeep.is_empty():
			continue
		var paid := _pay(actor, def.requirement)
		var was := is_suspended(slot)
		if paid and was:
			_suspended.erase(slot)
			changed.append(slot)
		elif not paid and not was:
			_suspended[slot] = true
			changed.append(slot)
	return changed


## Pay one interval, or refuse. Base pools only, so an item cannot fund its own
## upkeep out of the stats it grants.
func _pay(actor: Actor, requirement: ItemRequirement) -> bool:
	for resource_id in requirement.upkeep:
		var amount := float(requirement.upkeep[resource_id])
		var reserve := float(requirement.upkeep_reserve.get(resource_id, 0.0))
		var pool := actor.resource(resource_id)
		if pool == null or pool.current - amount < reserve:
			return false
	for resource_id in requirement.upkeep:
		var pool := actor.resource(resource_id)
		pool.current -= float(requirement.upkeep[resource_id])
	return true
