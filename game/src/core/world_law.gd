class_name WorldLawState
extends RefCounted

## One imprinted law on a created world (ADR 0019). Laws are grouped into
## six categories: spatial, temporal, elemental, physical, life, qi.

const SPATIAL := &"spatial"
const TEMPORAL := &"temporal"
const ELEMENTAL := &"elemental"
const PHYSICAL := &"physical"
const LIFE := &"life"
const QI := &"qi"

var law_id: StringName
var group: StringName = SPATIAL
var value: float = 1.0
var locked: bool = false


func _init(p_law_id: StringName = &"", p_group: StringName = SPATIAL, p_value: float = 1.0) -> void:
	law_id = p_law_id
	group = p_group
	value = p_value


func to_dict() -> Dictionary:
	return {
		"law_id": String(law_id),
		"group": String(group),
		"value": value,
		"locked": locked,
	}


static func from_dict(data: Dictionary) -> WorldLawState:
	var law := WorldLawState.new(
		StringName(data.get("law_id", "")),
		StringName(data.get("group", SPATIAL)),
		float(data.get("value", 1.0))
	)
	law.locked = bool(data.get("locked", false))
	return law
