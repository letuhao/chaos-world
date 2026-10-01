class_name ItemInstance
extends RefCounted

## A unique item instance (equipment/quest): definition id plus per-instance state
## such as durability, refinement, affixes, and binding (ADR 0007).

var def_id: StringName
var instance_id: StringName
var durability: float = 1.0
var refinement: int = 0
var affixes: Array[StringName] = []
var bound_to: StringName = &""


func _init(p_def_id: StringName = &"", p_instance_id: StringName = &"") -> void:
	def_id = p_def_id
	instance_id = p_instance_id


func to_dict() -> Dictionary:
	var affix_out: Array = []
	for affix in affixes:
		affix_out.append(String(affix))
	return {
		"def_id": String(def_id),
		"instance_id": String(instance_id),
		"durability": durability,
		"refinement": refinement,
		"affixes": affix_out,
		"bound_to": String(bound_to),
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	var instance := ItemInstance.new(
		StringName(data.get("def_id", "")), StringName(data.get("instance_id", ""))
	)
	instance.durability = float(data.get("durability", 1.0))
	instance.refinement = int(data.get("refinement", 0))
	instance.bound_to = StringName(data.get("bound_to", ""))
	for affix in data.get("affixes", []):
		instance.affixes.append(StringName(affix))
	return instance
