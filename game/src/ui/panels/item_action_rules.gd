class_name ItemActionRules
extends RefCounted

## Why an item action is or is not available, and which slot it would use.
##
## Pure decisions over primitives: the screen holds the node tree and the
## formatting, this holds the rules. It reads the facade and `core` only, so it
## stays inside the `ui/` boundary rule and stays headless-testable.
##
## These mirror the facade's preconditions for *feedback*. The facade's own
## decision is still authoritative — every caller acts through it and treats a
## rejection as final.

## Activation channels an item can actually be used for. These are the plain
## lowercase ids `ItemDef.activation()` returns; `ui/` may not name the items
## module's `ItemActivation` constants, so they are spelled out here and the
## mismatch is caught by the `not_usable` path rather than by a silent success.
const USABLE_ACTIVATIONS: Array[StringName] = [&"consumed", &"learned", &"property"]

const REASON_NONE := ""
const REASON_NO_SELECTION := "no_selection"
const REASON_NO_ACTOR := "no_actor"
const REASON_NOT_CARRIED := "not_carried"
const REASON_NOT_EQUIPMENT := "not_equipment"
const REASON_NOT_USABLE := "not_usable"
const REASON_SLOT_EMPTY := "slot_empty"
const REASON_INVENTORY_FULL := "inventory_full"
const REASON_BOUND_TO_OTHER := "bound_to_other"
const REASON_REALM_TIER_TOO_LOW := "realm_tier_too_low"


## `""` when the selected item may be used.
static func use_block_reason(actor: Actor, row: Dictionary) -> String:
	if row.is_empty() or row.get("def") == null:
		return REASON_NO_SELECTION
	if not USABLE_ACTIVATIONS.has(StringName(row["def"].activation())):
		return REASON_NOT_USABLE
	if actor == null or not ItemsApi.has_item(actor, StringName(row["def_id"])):
		return REASON_NOT_CARRIED
	return REASON_NONE


## `""` when the selected item may be equipped, combining shape and requirements.
static func equip_block_reason(actor: Actor, row: Dictionary) -> String:
	var shape := equip_shape_reason(actor, row)
	if shape != REASON_NONE:
		return shape
	return equip_requirement_reason(actor, row)


## Whether the selection is an equippable thing the actor actually carries.
static func equip_shape_reason(actor: Actor, row: Dictionary) -> String:
	if row.is_empty() or row.get("def") == null:
		return REASON_NO_SELECTION
	if not row["def"].is_equipment():
		return REASON_NOT_EQUIPMENT
	if actor == null:
		return REASON_NO_ACTOR
	var inventory := ItemsApi.inventory(actor)
	if inventory == null or inventory.find_instance(StringName(row["def_id"])) == null:
		return REASON_NOT_CARRIED
	return REASON_NONE


## Whether the actor satisfies the requirements the equipment layer enforces: the
## grade gate and the item's binding.
static func equip_requirement_reason(actor: Actor, row: Dictionary) -> String:
	if actor == null:
		return REASON_NO_ACTOR
	var gate := realm_block_reason(actor, row["def"])
	if gate != REASON_NONE:
		return gate
	var bound := StringName(String(row.get("bound_to", "")))
	if bound != &"" and bound != actor.id:
		return REASON_BOUND_TO_OTHER
	return REASON_NONE


## `""` when the chosen slot can be emptied into the inventory.
static func unequip_block_reason(actor: Actor, slot: StringName) -> String:
	if actor == null:
		return REASON_NO_ACTOR
	var equipment := ItemsApi.equipment(actor)
	if equipment == null or equipment.definition(slot) == null:
		return REASON_SLOT_EMPTY
	var inventory := ItemsApi.inventory(actor)
	if inventory != null and inventory.is_full():
		return REASON_INVENTORY_FULL
	return REASON_NONE


## The grade gate the equipment layer applies: the actor's realm tier must meet
## the item's required tier. An actor on no path is ungated.
static func realm_block_reason(actor: Actor, def: Resource) -> String:
	var realm: StringName = actor.realm()
	if realm == &"":
		return REASON_NONE
	var tier := RealmDefaults.ladder().tier_of(realm)
	if tier > 0 and tier < def.required_tier():
		return REASON_REALM_TIER_TOO_LOW
	return REASON_NONE


## The slot the selected row would go into: the slot its subtype authorises, the
## first free accessory slot for a two-slot subtype, otherwise whatever the player
## chose.
##
## The rule is asked of the items module through the facade rather than restated
## here — a second copy in `ui/` is the drift this avoids. An empty answer means
## the subtype expresses no opinion, so the player's own choice stands.
static func slot_for(actor: Actor, row: Dictionary, chosen: StringName) -> StringName:
	var def: Resource = row.get("def", null)
	if actor == null or def == null:
		return chosen
	var equipment := ItemsApi.equipment(actor)
	if equipment == null:
		return chosen
	var allowed := equipment.slots_for(def)
	if allowed.size() == 1:
		return allowed[0]
	if allowed.size() > 1:
		return free_accessory_slot(actor, def)
	return chosen


## First empty slot among those `def`'s subtype authorises, or the first of them
## when all are taken. The candidate slots come from the items module, so this
## panel names no slot id of its own.
static func free_accessory_slot(actor: Actor, def: Resource) -> StringName:
	var equipment := ItemsApi.equipment(actor)
	if equipment == null or def == null:
		return &""
	var allowed := equipment.slots_for(def)
	if allowed.is_empty():
		return &""
	for slot in allowed:
		if equipment.definition(slot) == null:
			return slot
	return allowed[0]
