class_name AcupointSet
extends RefCounted

## Container for an actor's acupoints (ADR 0015). Stored as a component on
## the actor; providers read from it.

var points: Array[Acupoint] = []

## Set while an acupoint-consuming action is in flight, so cultivation and
## breakthrough cannot interleave on the same points.
var busy: bool = false


func _init(p_points: Array[Acupoint] = []) -> void:
	points = p_points


## Bring the set in line with `realm_id`: add acupoints the realm has unlocked
## and re-derive every capacity from its definition scaled by the meridian
## network's capacity bonus. Idempotent — stored essence, quality, and blocked
## flags survive repeat calls.
func synchronize(realm_id: StringName, capacity_bonus: float) -> void:
	var by_id := {}
	for point in points:
		by_id[point.id] = point
	for def in AcupointDefaults.definitions():
		if def.unlock_index > maxi(0, RealmDefaults.ladder().index_of(realm_id)):
			continue
		var scaled := def.base_capacity * (1.0 + capacity_bonus)
		var point: Acupoint = by_id.get(def.id)
		if point == null:
			point = AcupointDefaults.from_definition(def)
			point.capacity = scaled
			points.append(point)
			continue
		point.capacity = scaled
		point.current = clampf(point.current, 0.0, scaled)


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
