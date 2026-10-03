class_name AcupointSet
extends RefCounted

## Container for an actor's acupoints (ADR 0015/0023). Stored as a component on
## the actor; providers read from it. Body essence is stored in the shared
## body_integrity ResourcePool, not per-acupoint; this set mediates access.

var points: Array[Acupoint] = []

## Re-entrancy guard on the acupoint-consuming verbs. Every window that sets it
## is synchronous and clears it before returning, so nothing observes it today;
## it exists because `MeridianNetwork.changed` and `Actor.path_advanced` fire
## *inside* those windows, and a handler on either would otherwise re-enter
## cultivate/strengthen/recover/attempt mid-mutation. Keep it a plain bool: an
## await inside a guarded window would make this genuinely observable, and the
## flag is what stops that from silently corrupting a body.
var busy: bool = false

## The shared body essence pool. Set by BodyTraining.synchronize from the
## actor's body_integrity resource. All fill/drain operations go through this
## pool so there is exactly one energy balance. The set mediates access and
## deliberately does not hand the pool out: read it through
## `actor.resource(BodyStats.BODY_INTEGRITY)`, mutate it through fill/drain.
var _pool: ResourcePool = null


func _init(p_points: Array[Acupoint] = []) -> void:
	points = p_points


## Set the shared body essence pool. Called by synchronize() after the
## actor's body_integrity resource is resolved.
func set_pool(pool: ResourcePool) -> void:
	_pool = pool


## Fill the shared pool by `amount`. Returns false when blocked or no pool.
func fill(amount: float) -> bool:
	if _pool == null or amount <= 0.0 or not is_finite(amount):
		return false
	_pool.change(amount)
	return true


## Drain the shared pool by `amount`. Returns false when blocked or no pool.
func drain(amount: float) -> bool:
	if _pool == null or amount <= 0.0 or not is_finite(amount):
		return false
	_pool.change(-amount)
	return true


## Bring the set in line with `realm_id`: add acupoints the realm has unlocked.
## Idempotent — quality and blocked flags survive repeat calls. The pool
## reference is preserved.
func synchronize(realm_id: StringName) -> void:
	var by_id := {}
	for point in points:
		by_id[point.id] = point
	for def in AcupointDefaults.definitions():
		if def.unlock_index > maxi(0, RealmDefaults.ladder().index_of(realm_id)):
			continue
		var point: Acupoint = by_id.get(def.id)
		if point == null:
			point = AcupointDefaults.from_definition(def)
			points.append(point)


func open_count() -> int:
	var count := 0
	for point in points:
		if not point.blocked:
			count += 1
	return count


func blocked_count() -> int:
	var count := 0
	for point in points:
		if point.blocked:
			count += 1
	return count


func average_quality() -> float:
	var open: Array[Acupoint] = []
	for point in points:
		if not point.blocked:
			open.append(point)
	if open.is_empty():
		return 0.0
	var sum := 0.0
	for point in open:
		sum += point.quality
	return sum / open.size()
