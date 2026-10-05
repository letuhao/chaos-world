class_name AcupointDefaults
extends RefCounted

## Acupoint layout per tier (ADR 0015/0023). Definitions are generated data
## under res://data/body_cultivation/acupoints; this class only enumerates them.
## Minor: 36 points (realms 1-9), Major: 12 (realms 10-18),
## Celestial: 12 (Immortal+).

const MINOR_COUNT := 36
const MAJOR_COUNT := 12
const CELESTIAL_COUNT := 12
const DATA_DIR := "res://data/body_cultivation/acupoints"

static var _defs: Array[AcupointDef] = []


## All acupoint definitions, loaded once and cached.
static func definitions() -> Array[AcupointDef]:
	if _defs.is_empty():
		_defs = _load_all()
	return _defs


## Acupoints an actor should hold at `realm_id`, built from the definitions whose
## unlock_index the realm has reached. Capacity is NOT taken from the definition:
## essence lives in the shared body_integrity pool (ADR 0012), and
## `AcupointDef.base_capacity` is authored but unread.
static func build_for_realm(realm_id: StringName) -> Array[Acupoint]:
	var realm_index := RealmDefaults.ladder().index_of(realm_id)
	if realm_index < 0:
		realm_index = 0
	var points: Array[Acupoint] = []
	for def in definitions():
		if def.unlock_index > realm_index:
			continue
		points.append(from_definition(def))
	return points


static func from_definition(def: AcupointDef) -> Acupoint:
	var point := Acupoint.new()
	point.id = def.id
	point.tier = def.tier
	point.quality = 0.5
	point.blocked = false
	return point


## The meridian an acupoint trains, or empty when the definition is unknown.
static func meridian_of(point_id: StringName) -> StringName:
	for def in definitions():
		if def.id == point_id:
			return def.meridian_id
	return &""


static func _load_all() -> Array[AcupointDef]:
	var defs: Array[AcupointDef] = []
	defs.append_array(_load_tier("minor", MINOR_COUNT))
	defs.append_array(_load_tier("major", MAJOR_COUNT))
	defs.append_array(_load_tier("celestial", CELESTIAL_COUNT))
	return defs


static func _load_tier(tier: String, count: int) -> Array[AcupointDef]:
	var defs: Array[AcupointDef] = []
	for i in count:
		var def := load("%s/%s_%d.tres" % [DATA_DIR, tier, i]) as AcupointDef
		if def != null:
			defs.append(def)
	return defs
