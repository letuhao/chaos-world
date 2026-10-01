class_name InhabitantRef
extends RefCounted

## A reference to a group of inhabitants in a created world (ADR 0019).
## Tracks type, count, and loyalty to the creator.

const PLANT := &"plant"
const BEAST := &"beast"
const HUMANOID := &"humanoid"
const ELEMENTAL := &"elemental"

var inhabitant_id: StringName
var type: StringName = PLANT
var count: int = 0
var loyalty: float = 0.5


func _init(
	p_id: StringName = &"", p_type: StringName = PLANT, p_count: int = 0, p_loyalty: float = 0.5
) -> void:
	inhabitant_id = p_id
	type = p_type
	count = p_count
	loyalty = p_loyalty


func to_dict() -> Dictionary:
	return {
		"inhabitant_id": String(inhabitant_id),
		"type": String(type),
		"count": count,
		"loyalty": loyalty,
	}


static func from_dict(data: Dictionary) -> InhabitantRef:
	return InhabitantRef.new(
		StringName(data.get("inhabitant_id", "")),
		StringName(data.get("type", PLANT)),
		int(data.get("count", 0)),
		float(data.get("loyalty", 0.5))
	)
