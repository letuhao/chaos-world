class_name RealmLadder
extends RefCounted

## Ordered realm ladder shared by every cultivation system (ADR 0005).

var _realms: Array[RealmDef] = []
var _index: Dictionary = {}


func _init(realms: Array[RealmDef]) -> void:
	_realms = realms
	for i in _realms.size():
		_realms[i].index = i
		_index[_realms[i].id] = _realms[i]


func size() -> int:
	return _realms.size()


func realms() -> Array[RealmDef]:
	return _realms


func has(id: StringName) -> bool:
	return _index.has(id)


func realm(id: StringName) -> RealmDef:
	return _index.get(id)


func index_of(id: StringName) -> int:
	var entry: RealmDef = _index.get(id)
	return -1 if entry == null else entry.index


func tier_of(id: StringName) -> int:
	var entry: RealmDef = _index.get(id)
	return 0 if entry == null else entry.tier


func next(id: StringName) -> RealmDef:
	var position := index_of(id)
	if position < 0 or position + 1 >= _realms.size():
		return null
	return _realms[position + 1]


func tier_realms(tier: int) -> Array[RealmDef]:
	var out: Array[RealmDef] = []
	for entry in _realms:
		if entry.tier == tier:
			out.append(entry)
	return out
