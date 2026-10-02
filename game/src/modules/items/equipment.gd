class_name Equipment
extends RefCounted

## Equipment slots (ADR 0007). Equipping applies an item's fixed and rolled
## effects exactly once, tagged with the owning instance's id; unequipping
## removes exactly that contribution (ADR 0026/0028). Observable.

signal changed

const WEAPON := &"weapon"
const ARMOR := &"armor"
const ACCESSORY_A := &"accessory_a"
const ACCESSORY_B := &"accessory_b"
const ARTIFACT := &"artifact"

const SLOTS := [WEAPON, ARMOR, ACCESSORY_A, ACCESSORY_B, ARTIFACT]

var _slots: Dictionary = {}
var _defs: Dictionary = {}
## Upkeep state for equipped items (ADR 0052). Null until the items module wires it,
## so a bare Equipment in a test behaves exactly as before.
var _upkeep: EquipmentUpkeep = null


## Bind the upkeep tracker. One per equipment component.
func set_upkeep(upkeep: EquipmentUpkeep) -> void:
	_upkeep = upkeep


func upkeep() -> EquipmentUpkeep:
	return _upkeep


func equipped(slot: StringName) -> ItemInstance:
	return _slots.get(slot)


func definition(slot: StringName) -> ItemDef:
	return _defs.get(slot)


func all() -> Dictionary:
	return _slots.duplicate()


## Effects currently contributed by the item in `slot`, for inspection UI.
func effects(slot: StringName) -> Array[Dictionary]:
	var instance: ItemInstance = _slots.get(slot)
	var def: ItemDef = _defs.get(slot)
	if def == null:
		return []
	# A suspended item is still equipped but contributes nothing (ADR 0052). This is
	# the whole of the upkeep consequence: no unequip, no equip cascade.
	if _upkeep != null and _upkeep.is_suspended(slot):
		return []
	return ItemEffects.resolve(def, instance)


func equip(actor: Actor, slot: StringName, def: ItemDef, instance: ItemInstance) -> bool:
	if not SLOTS.has(slot):
		return false
	if def == null or instance == null or not def.is_equipment():
		return false
	if instance.def_id != def.id:
		return false
	if not _meets_requirements(actor, def, instance):
		return false
	# Replacing a slot is atomic: validate first, then swap, so an invalid
	# replacement leaves the current equipment intact.
	var previous: ItemInstance = _slots.get(slot)
	var previous_def: ItemDef = _defs.get(slot)
	if previous != null:
		actor.stats.remove_modifiers_from(previous.instance_id)
	_slots[slot] = instance
	_defs[slot] = def
	for modifier in ItemEffects.stat_modifiers(
		ItemEffects.resolve(def, instance), instance.instance_id
	):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(
		ItemEffects.resolve(def, instance), instance.instance_id
	):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()
	changed.emit()
	return true


func unequip(actor: Actor, slot: StringName) -> ItemInstance:
	var instance: ItemInstance = _slots.get(slot)
	if instance == null:
		return null
	actor.stats.remove_modifiers_from(instance.instance_id)
	_slots.erase(slot)
	_defs.erase(slot)
	actor.mark_stats_dirty()
	changed.emit()
	return instance


## Recompute a slot's contribution from scratch: removes the previous effects and
## adds the current ones exactly once, so rebuilding cannot accumulate drift.
func rebuild(actor: Actor, slot: StringName) -> bool:
	var instance: ItemInstance = _slots.get(slot)
	var def: ItemDef = _defs.get(slot)
	if instance == null or def == null:
		return false
	actor.stats.remove_modifiers_from(instance.instance_id)
	var effects := ItemEffects.resolve(def, instance)
	for modifier in ItemEffects.stat_modifiers(effects, instance.instance_id):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(effects, instance.instance_id):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()
	changed.emit()
	return true


## Optional requirement profile check (ADR 0052). Runs alongside the tier and
## binding checks rather than replacing them, and reads only base attributes, so an
## item can never satisfy a requirement with the stats it grants.
func _meets_profile(actor: Actor, def: ItemDef) -> bool:
	if def.requirement == null:
		return true
	return def.requirement.satisfied_by(actor)


func _meets_requirements(actor: Actor, def: ItemDef, instance: ItemInstance) -> bool:
	if not _meets_profile(actor, def):
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
	return true
