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

## Why the last [method equip] returned false. Empty after a success.
##
## Every refusal used to be a bare `return false`, so a caller could not tell a
## full inventory from a wrong slot from unmet requirements, and no test could
## name the branch it was exercising.
const REASON_NO_SUCH_SLOT := "no_such_slot"
const REASON_NOT_EQUIPMENT := "not_equipment"
const REASON_INSTANCE_MISMATCH := "instance_mismatch"
const REASON_REQUIREMENTS_UNMET := "requirements_unmet"
const REASON_WRONG_SLOT := "wrong_slot_for_subtype"
## The definition's subtype is authored as wearing nowhere — a socket payload,
## not something a body puts on. Its own branch, because "wrong slot" would name
## a slot the rule never offered and send a caller looking for a fix that does
## not exist.
const REASON_UNWEARABLE := "unwearable_subtype"

var _last_refusal: String = ""

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


## The slots `def` may be equipped into, or `[]` when the subtype expresses no
## opinion.
##
## Empty is deliberately not "every slot": it means this rule has nothing to say
## about that subtype, which is different from ruling every slot in. A caller that
## wants the effective set unions this with [constant SLOTS]. That distinction is
## what lets `ui/` ask for a suggestion without having to restate the rule: a
## non-empty answer is a real constraint, an empty one means "leave it to the
## player".
##
## The rule itself is authored content read by [ItemSlots], so a subtype nobody
## declared here is still ruled on if the content tree rules it. A subtype
## authored as wearing nowhere also answers `[]` here; [method equip] refuses it
## on its own branch, and [method is_wearable] is how a caller tells the two
## apart before offering the player a choice that cannot succeed.
func slots_for(def: ItemDef) -> Array[StringName]:
	if def == null:
		return []
	return ItemSlots.for_subtype(def.subcategory)


## Whether `def` may be worn at all. False only for a subtype the authored rule
## places in no wearable slot.
func is_wearable(def: ItemDef) -> bool:
	return def == null or ItemSlots.is_wearable(def.subcategory)


## Why the last [method equip] refused, or `""` when it succeeded. Read it after
## a `false` to name the branch; never a substitute for the boolean.
func last_refusal() -> String:
	return _last_refusal


func equip(actor: Actor, slot: StringName, def: ItemDef, instance: ItemInstance) -> bool:
	_last_refusal = ""
	var refused := _refusal_for(actor, slot, def, instance)
	if not refused.is_empty():
		return _refuse(refused)
	# Replacing a slot is atomic: validate first, then swap, so an invalid
	# replacement leaves the current equipment intact.
	var previous: ItemInstance = _slots.get(slot)
	var previous_def: ItemDef = _defs.get(slot)
	if previous != null:
		actor.stats.remove_modifiers_from(previous.instance_id)
	_slots[slot] = instance
	_defs[slot] = def
	# Suspension is per slot, so swapping INTO a suspended slot must not hand the
	# incoming item the outgoing one's contribution back (ADR 0052, DEF-0088). The
	# new item is equipped and inert until upkeep is paid again.
	var applied: Array[Dictionary] = []
	if not _is_suspended(slot):
		applied = ItemEffects.resolve(def, instance)
	for modifier in ItemEffects.stat_modifiers(applied, instance.instance_id):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(applied, instance.instance_id):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()
	changed.emit()
	return true


## Why this equip must be refused, or `""` when it is legal.
##
## Every guard [method equip] applies is a pure read of the arguments, so they live
## here and `equip` keeps a single refusal exit — which is what the `REASON_*`
## constants exist for: a caller naming the branch it hit, instead of one left
## guessing from a bare `false`.
##
## The two halves are the ones the two checks already were: does this request even
## name a wearable item for this slot, and then does policy allow it. Half one runs
## first because a half-two check dereferences a `def` that half one may have refused.
func _refusal_for(actor: Actor, slot: StringName, def: ItemDef, instance: ItemInstance) -> String:
	var reason := _request_refusal(slot, def, instance)
	if reason.is_empty():
		reason = _policy_refusal(actor, slot, def, instance)
	return reason


## The well-formedness half, or `""` when the request names a real item of this kind.
##
## Order matters and is load-bearing. `REASON_NOT_EQUIPMENT` precedes
## `REASON_INSTANCE_MISMATCH` because a null `def` has no `id` to compare against.
func _request_refusal(slot: StringName, def: ItemDef, instance: ItemInstance) -> String:
	if not SLOTS.has(slot):
		return REASON_NO_SUCH_SLOT
	if def == null or instance == null or not def.is_equipment():
		return REASON_NOT_EQUIPMENT
	if instance.def_id != def.id:
		return REASON_INSTANCE_MISMATCH
	return ""


## The policy half: authored slot rule, unwearability, then requirements.
func _policy_refusal(
	actor: Actor, slot: StringName, def: ItemDef, instance: ItemInstance
) -> String:
	# Unwearable is checked before the slot rule because a subtype ruled to no slot
	# at all answers `[]` too, so only that branch can refuse it, and naming it
	# "wrong_slot" would point a caller at a slot the rule never offered.
	if not is_wearable(def):
		return REASON_UNWEARABLE
	# A weapon in the armour slot is not a stylistic choice: the slot decides which
	# upkeep and which suspension the item pays, so a mismatch would charge the
	# wrong cost. Refused here rather than tolerated. An empty answer is no
	# opinion, so it restricts nothing.
	var allowed := slots_for(def)
	if not allowed.is_empty() and not allowed.has(slot):
		return REASON_WRONG_SLOT
	if not _meets_requirements(actor, def, instance):
		return REASON_REQUIREMENTS_UNMET
	return ""


## Record why an equip was refused and report the failure. One helper so every
## refusal sets the reason; a bare `return false` would leave it stale.
func _refuse(reason: String) -> bool:
	_last_refusal = reason
	return false


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
	# The remove-then-add above runs unconditionally, so a suspended slot ends the
	# rebuild with nothing applied — the same "equipped but contributes nothing"
	# result effects() reports. Rebuilding must never hand a suspended item its
	# modifiers back (DEF-0088).
	var applied: Array[Dictionary] = []
	if not _is_suspended(slot):
		applied = ItemEffects.resolve(def, instance)
	for modifier in ItemEffects.stat_modifiers(applied, instance.instance_id):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(applied, instance.instance_id):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()
	changed.emit()
	return true


## True when upkeep has suspended this slot. Null upkeep means nothing is ever
## suspended, so a bare Equipment behaves exactly as it did before ADR 0052.
func _is_suspended(slot: StringName) -> bool:
	return _upkeep != null and _upkeep.is_suspended(slot)


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
