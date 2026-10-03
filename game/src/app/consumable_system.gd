class_name ConsumableSystem
extends RefCounted

## Manages 6 quick-use consumable slots.
## Slots hold item def_ids; use delegates to ItemsApi.

const SLOT_COUNT := 6
const MODULE_KEY := &"consumable_slots"

var _slots: Array = []
var _actor: Actor


func _init(actor: Actor) -> void:
	_actor = actor
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = &""
	_load()


func assign_consumable(slot_index: int, def_id: StringName, quantity: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	if def_id == &"" or quantity <= 0:
		return {"ok": false, "reason": "invalid_item"}
	_slots[slot_index] = def_id
	_save()
	return {"ok": true, "slot": slot_index, "def_id": String(def_id), "quantity": quantity}


func unassign_consumable(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	var prev: StringName = _slots[slot_index]
	_slots[slot_index] = &""
	_save()
	return {"ok": true, "slot": slot_index, "prev_def_id": String(prev)}


func use_consumable(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	var def_id: StringName = _slots[slot_index]
	if def_id == &"":
		return {"ok": false, "reason": "empty_slot", "slot": slot_index}
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	var result: Dictionary = ItemsApi.use_item(_actor, def_id, 1)
	if bool(result.get("ok", false)):
		# Auto-unassign if stack depleted.
		if not ItemsApi.has_item(_actor, def_id, 1):
			_slots[slot_index] = &""
			_save()
	return result


func slot_count() -> int:
	return SLOT_COUNT


## Reset all slots for test isolation.
func reset() -> void:
	for i in SLOT_COUNT:
		_slots[i] = &""
	_save()


func def_id_at(slot_index: int) -> StringName:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return &""
	return _slots[slot_index]


func summary() -> Dictionary:
	var slots: Array = []
	for i in SLOT_COUNT:
		var def_id: StringName = _slots[i]
		var quantity := 0
		if _actor != null and def_id != &"":
			quantity = ItemsApi.inventory(_actor).count(def_id)
		(
			slots
			. append(
				{
					"index": i,
					"def_id": String(def_id),
					"quantity": quantity,
				}
			)
		)
	return {
		"slot_count": SLOT_COUNT,
		"slots": slots,
	}


func _save() -> void:
	if _actor == null:
		return
	var data: Array = []
	for i in SLOT_COUNT:
		data.append(String(_slots[i]))
	_actor.set_module_data(MODULE_KEY, {"slots": data})


func _load() -> void:
	if _actor == null:
		return
	var data: Dictionary = _actor.get_module_data(MODULE_KEY)
	if data.is_empty():
		return
	var slots: Array = data.get("slots", [])
	for i in mini(slots.size(), SLOT_COUNT):
		_slots[i] = StringName(slots[i])
