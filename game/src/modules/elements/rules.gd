class_name ElementRules
extends RefCounted

## Pure element relationship rules, built from ElementDefs (ADR 0004).

const NEUTRAL := 1.0
const STRONG := 1.5
const WEAK := 0.5
const NOURISH := 0.75

var _defs: Dictionary = {}


func _init(defs: Array[ElementDef]) -> void:
	for entry in defs:
		_defs[entry.id] = entry


func has(id: StringName) -> bool:
	return _defs.has(id)


func element(id: StringName) -> ElementDef:
	return _defs.get(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(key)
	return out


func overcomes(attacker: StringName, defender: StringName) -> bool:
	var entry: ElementDef = _defs.get(attacker)
	return entry != null and entry.overcomes.has(defender)


func generates(attacker: StringName, defender: StringName) -> bool:
	var entry: ElementDef = _defs.get(attacker)
	return entry != null and entry.generates.has(defender)


func weak_against(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _defs.keys():
		var entry: ElementDef = _defs[key]
		if entry.overcomes.has(id):
			out.append(key)
	return out


func multiplier(attacker: StringName, defender: StringName) -> float:
	if attacker == defender:
		return NEUTRAL
	if overcomes(attacker, defender):
		return STRONG
	if overcomes(defender, attacker):
		return WEAK
	if generates(attacker, defender):
		return NOURISH
	return NEUTRAL
