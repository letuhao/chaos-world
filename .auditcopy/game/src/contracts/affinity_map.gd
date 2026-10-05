class_name AffinityMap
extends RefCounted

## Observable element-affinity map. Emits `changed` on mutation so an actor's stat
## cache invalidates automatically — no direct-mutation footgun.

signal changed

var _values: Dictionary = {}


func set_value(id: StringName, value: float) -> void:
	_values[id] = value
	changed.emit()


func get_value(id: StringName) -> float:
	return float(_values.get(id, 0.0))


func has(id: StringName) -> bool:
	return _values.has(id)


func ids() -> Array:
	return _values.keys()


func to_dict() -> Dictionary:
	return _values.duplicate()


func set_dict(data: Dictionary) -> void:
	_values.clear()
	for key in data.keys():
		_values[key] = data[key]
	changed.emit()


func clear() -> void:
	_values.clear()
	changed.emit()
