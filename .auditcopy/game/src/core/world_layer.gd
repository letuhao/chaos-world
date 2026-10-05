class_name WorldLayerState
extends RefCounted

## One spatial layer of a created world (ADR 0019). Layers divide the world
## into regions (surface, underground, heaven, void) with their own law set.

var layer_id: StringName
var name: String = ""
var size_ratio: float = 1.0
var laws: Array[StringName] = []


func _init(p_layer_id: StringName = &"", p_name: String = "", p_size_ratio: float = 1.0) -> void:
	layer_id = p_layer_id
	name = p_name
	size_ratio = p_size_ratio


func to_dict() -> Dictionary:
	return {
		"layer_id": String(layer_id),
		"name": name,
		"size_ratio": size_ratio,
		"laws": _string_array(laws),
	}


static func from_dict(data: Dictionary) -> WorldLayerState:
	var layer := WorldLayerState.new(
		StringName(data.get("layer_id", "")),
		String(data.get("name", "")),
		float(data.get("size_ratio", 1.0))
	)
	for law_id in data.get("laws", []):
		layer.laws.append(StringName(law_id))
	return layer


func _string_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
