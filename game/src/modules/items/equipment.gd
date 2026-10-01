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
	if not def.is_equipment():
		return false
	if instance.def_id != def.id:
		return false
	# Grade/realm requirement: the actor's realm tier must meet the item's grade.
	var actor_realm := actor.realm()
	if actor_realm != &"":
		var actor_tier := RealmDefaults.ladder().tier_of(actor_realm)
		if actor_tier > 0 and actor_tier < def.required_tier():
			return false
	# Binding: a bound item equips only for its owner.
	if instance.bound_to != &"" and instance.bound_to != actor.id:
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
