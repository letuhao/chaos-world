class_name MeridianNetwork
extends RefCounted

## Shared meridian network (ADR 0017). Core infrastructure for all cultivation
## systems. Meridians unlock with realm, progress through states, and grant
## flow/capacity/power bonuses.

var _meridians: Dictionary = {}


func unlock_for_realm(realm_id: StringName) -> void:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(realm_id)
	if realm_index < 0:
		return
	for def in MeridianDefaults.all():
		if def.tier <= realm_index and not _meridians.has(def.id):
			_meridians[def.id] = _state_from_def(def)


func get_meridian(id: StringName) -> MeridianState:
	return _meridians.get(id)


func open_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"closed":
		state.state = &"open"


func expand_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"open":
		state.state = &"expanded"


func strengthen_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"expanded":
		state.state = &"strengthened"


func damage_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null:
		state.state = &"damaged"


func repair_meridian(id: StringName) -> void:
	var state := get_meridian(id)
	if state != null and state.state == &"damaged":
		state.state = &"open"


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
			total += state.power_bonus * state.get_bonus()
	return total


func to_dict() -> Dictionary:
	var out := {}
	for key in _meridians.keys():
		var state: MeridianState = _meridians[key]
		out[String(key)] = {
			"id": String(state.id),
			"state": String(state.state),
			"tier": state.tier,
			"capacity_bonus": state.capacity_bonus,
			"flow_bonus": state.flow_bonus,
			"power_bonus": state.power_bonus,
		}
	return out


static func from_dict(data: Dictionary) -> MeridianNetwork:
	var network := MeridianNetwork.new()
	for key in data.keys():
		var entry = data[key]
		var state := MeridianState.new()
		state.id = StringName(entry.get("id", ""))
		state.state = StringName(entry.get("state", "closed"))
		state.tier = int(entry.get("tier", 0))
		state.capacity_bonus = float(entry.get("capacity_bonus", 0.0))
		state.flow_bonus = float(entry.get("flow_bonus", 0.0))
		state.power_bonus = float(entry.get("power_bonus", 0.0))
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
