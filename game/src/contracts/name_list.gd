class_name NameList
extends RefCounted

## Observable list of StringName ids. Emits `changed` on mutation so stat caches
## invalidate automatically. Used for actor traits and path unlocks.

signal changed

var _values: Array[StringName] = []


func add(id: StringName) -> void:
	if _values.has(id):
		return
	_values.append(id)
	changed.emit()


func remove(id: StringName) -> void:
	if not _values.has(id):
		return
	_values.erase(id)
	changed.emit()


func has(id: StringName) -> bool:
	return _values.has(id)


func size() -> int:
	return _values.size()


func values() -> Array[StringName]:
	return _values.duplicate()


func set_values(data: Array) -> void:
	_values.clear()
	for value in data:
		_values.append(StringName(value))
	changed.emit()


func to_array() -> Array:
	var out: Array = []
	for value in _values:
		out.append(String(value))
	return out
