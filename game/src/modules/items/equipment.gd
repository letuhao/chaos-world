class_name Equipment
extends RefCounted

## Equipment slots. Equipping applies source-tagged stat modifiers to an actor;
## unequipping removes them (ADR 0007). Observable.

signal changed

const WEAPON := &"weapon"
const ARMOR := &"armor"
const ACCESSORY_A := &"accessory_a"
const ACCESSORY_B := &"accessory_b"
const ARTIFACT := &"artifact"

const SLOTS := [WEAPON, ARMOR, ACCESSORY_A, ACCESSORY_B, ARTIFACT]

var _slots: Dictionary = {}


func equipped(slot: StringName) -> ItemInstance:
	return _slots.get(slot)


func all() -> Dictionary:
	return _slots.duplicate()


func equip(actor: Actor, slot: StringName, def: ItemDef, instance: ItemInstance) -> bool:
	if not SLOTS.has(slot):
		return false
	if _slots.has(slot):
		unequip(actor, slot)
	_slots[slot] = instance
	for modifier in def.build_modifiers(instance.instance_id):
		actor.stats.add_modifier(modifier)
	changed.emit()
	return true


func unequip(actor: Actor, slot: StringName) -> ItemInstance:
	var instance: ItemInstance = _slots.get(slot)
	if instance == null:
		return null
	actor.stats.remove_modifiers_from(instance.instance_id)
	_slots.erase(slot)
	changed.emit()
	return instance
