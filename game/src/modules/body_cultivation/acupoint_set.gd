class_name AcupointSet
extends RefCounted

## Container for an actor's acupoints (ADR 0015). Stored as a component on
## the actor; providers read from it.

var points: Array[Acupoint] = []


func _init(p_points: Array[Acupoint] = []) -> void:
	points = p_points


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
