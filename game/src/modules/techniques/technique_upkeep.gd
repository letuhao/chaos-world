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

## The shortest interval a technique may author. Anything below this would settle
## every frame regardless of what it asked for, so a zero or negative `upkeep_interval`
## degrades to "not every frame" instead of "every frame".
const MIN_INTERVAL := 1.0

## technique_id -> true when suspended. Absent means active.
var _suspended: Dictionary = {}

## Seconds accumulated toward the next settlement. `settle` charges a technique's
## upkeep IMMEDIATELY, so a caller that invokes it per frame would drain the pool
## sixty times a second and make every upkeep unaffordable within a second. The
## accumulator is what lets the composition root's frame tick (`StatusLoop.tick`,
## ADR 0089) drive upkeep on the same clock as statuses and bonds without either
## system owning a clock of its own.
var _elapsed: float = 0.0


func is_suspended(technique_id: StringName) -> bool:
	return _suspended.get(technique_id, false)


func suspended() -> Array[StringName]:
	var out: Array[StringName] = []
	for technique_id in _suspended.keys():
		out.append(technique_id)
	return out


func clear() -> void:
	_suspended.clear()
	_elapsed = 0.0


## Accumulate `delta` and settle only when an interval has genuinely elapsed. Returns
## the ids that changed state on THIS call, so a caller pays for a rebuild only when
## something moved. A `settle` that finds nothing due is free.
func advance(actor: Actor, delta: float, equipped: Array[StringName]) -> Array[StringName]:
	if actor == null:
		return []
	_elapsed += maxf(0.0, delta)
	var interval := _shortest_interval(equipped)
	# The epsilon is not cosmetic. A frame tick adds 1/60 sixty times, and float
	# accumulation lands that sum a hair UNDER 60.0 — so a strict `<` never fires at
	# exactly one interval and a 60-second upkeep silently never charges. The
	# tolerance is far below MIN_INTERVAL, so it can never settle early by a
	# meaningful amount.
	if interval <= 0.0 or _elapsed < interval - 0.001:
		return []
	_elapsed -= interval
	return settle(actor, equipped)


## The shortest authored interval among the equipped techniques that declare upkeep,
## or 0 when none do. The shortest wins so no technique is ever charged late, and
## `MIN_INTERVAL` bounds a zero that would otherwise settle on every frame.
func _shortest_interval(equipped: Array[StringName]) -> float:
	var shortest := 0.0
	for technique_id in equipped:
		var def := TechniqueCatalog.instance().definition(technique_id)
		if def == null or def.upkeep.is_empty():
			continue
		var interval := maxf(def.upkeep_interval, MIN_INTERVAL)
		if shortest <= 0.0 or interval < shortest:
			shortest = interval
	return shortest


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
