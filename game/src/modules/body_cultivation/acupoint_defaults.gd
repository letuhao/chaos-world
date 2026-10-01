class_name AcupointDefaults
extends RefCounted

## Acupoint layout per tier (ADR 0015). Minor: 36 points (realms 1-9),
## Major: 12 points (realms 10-18). Celestial reserved for Immortal+.

const MINOR_COUNT := 36
const MAJOR_COUNT := 12
const MINOR_BASE_CAPACITY := 50.0
const MAJOR_BASE_CAPACITY := 200.0


static func build_for_realm(realm_id: StringName) -> Array[Acupoint]:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(realm_id)
	# Default to realm 0 (Mortal) when no path is set or realm not found
	if realm_index < 0:
		realm_index = 0
	var points: Array[Acupoint] = []
	# Minor acupoints unlock from realm 0
	for i in MINOR_COUNT:
		points.append(_make(&"minor_%d" % i, Acupoint.MINOR, MINOR_BASE_CAPACITY))
	# Major acupoints unlock at Spirit tier (index 9+)
	if realm_index >= 9:
		for i in MAJOR_COUNT:
			points.append(_make(&"major_%d" % i, Acupoint.MAJOR, MAJOR_BASE_CAPACITY))
	return points


static func _make(id: StringName, tier: StringName, capacity: float) -> Acupoint:
	var point := Acupoint.new()
	point.id = id
	point.tier = tier
	point.capacity = capacity
	point.current = 0.0
	point.quality = 0.5
	point.blocked = false
	return point
