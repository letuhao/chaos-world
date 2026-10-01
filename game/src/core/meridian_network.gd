class_name MeridianNetwork
extends RefCounted

## Shared meridian network (ADR 0017). Core infrastructure for all cultivation
## systems. Meridians unlock with realm, progress through states, and grant
## flow/capacity/power bonuses. Injury is a recoverable overlay — it never
## erases structural attainment.

signal changed

## Each refinement step on a strengthened meridian adds this fraction of its
## base power bonus. Depth is raised by body-cultivation training (ADR 0023).
const REFINE_POWER_STEP := 0.1

var _meridians: Dictionary = {}


func unlock_for_realm(realm_id: StringName) -> void:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(realm_id)
	if realm_index < 0:
		return
	for def in MeridianDefaults.all():
		if def.tier <= realm_index and not _meridians.has(def.id):
			_meridians[def.id] = _state_from_def(def)
	_emit_changed()


func get_meridian(id: StringName) -> MeridianState:
	return _meridians.get(id)


func open_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"closed":
		state.state = &"open"
		_emit_changed()


func expand_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"open":
		state.state = &"expanded"
		_emit_changed()


func strengthen_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"expanded":
		state.state = &"strengthened"
		_emit_changed()


## Raise training depth on an already-strengthened meridian. `max_refinement` is
## supplied by the caller (the per-realm cap lives in module data, ADR 0023) so
## core stays free of module references. True when depth actually advanced.
func refine_meridian(id: StringName, max_refinement: int) -> bool:
	var state := get_meridian(id)
	if state == null or state.state != &"strengthened":
		return false
	if state.refinement >= max_refinement:
		return false
	state.refinement += 1
	_emit_changed()
	return true


## Apply recoverable injury. Structural state is preserved; bonuses are halved
## until repaired.
func damage_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null:
		state.injured = true
		_emit_changed()


## Repair injury. Restores previous attained benefits.
func repair_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.injured:
		state.injured = false
		_emit_changed()


func get_flow_bonus() -> float:
	var total := 0.0
	for state in _meridians.values():
		if state.is_open():
			total += state.flow_bonus * state.get_bonus()
	return total


func get_capacity_bonus() -> float:
	var total := 0.0
	for state in _meridians.values():
		if state.state == &"expanded" or state.state == &"strengthened":
			total += state.capacity_bonus * state.get_bonus()
	return total


func get_power_bonus() -> float:
	var total := 0.0
	for state in _meridians.values():
		if state.state == &"strengthened":
			var depth: float = 1.0 + REFINE_POWER_STEP * float(state.refinement)
			total += state.power_bonus * state.get_bonus() * depth
	return total


func to_dict() -> Dictionary:
	var out := {}
	for key in _meridians.keys():
		var state: MeridianState = _meridians[key]
		out[String(key)] = state.to_dict()
	return out


static func from_dict(data: Dictionary) -> MeridianNetwork:
	var network := MeridianNetwork.new()
	for key in data.keys():
		var entry = data[key]
		var state := MeridianState.from_dict(entry)
		network._meridians[state.id] = state
	return network


func _state_from_def(def: MeridianDef) -> MeridianState:
	var state := MeridianState.new()
	state.id = def.id
	state.state = &"closed"
	state.tier = def.tier
	state.capacity_bonus = def.capacity_bonus
	state.flow_bonus = def.flow_bonus
	state.power_bonus = def.power_bonus
	return state


func _emit_changed() -> void:
	changed.emit()
