class_name ItemTeardown
extends RefCounted

## The sink for unwanted equipment: torn down, it pays [TeardownYield]'s materials.
##
## ## Why this exists
##
## The bag is finite (24 slots by default), eight authored subtypes compete for
## five wearable slots, and the drop tables guarantee wearables — so equipment
## accrues with nowhere to go, and a guaranteed pickup eventually stops fitting.
## A resource generated with no place to spend it is the defect; this is the
## place to spend it. The payout is CRAFTING MATERIAL, so the loop closes against
## machinery that already exists ([Crafting]) rather than a second currency.
##
## ## It is also the undo for a mistaken equip
##
## Five slots and eight subtypes means a player WILL equip the wrong piece —
## a bandolier cannot be worn beside greaves and armour. [method
## ItemsApi.unequip_to_inventory] returns it; this converts it into something
## spendable. The [constant REASON_EQUIPPED] refusal is the seam between the two:
## a worn piece must come off before it can be broken down, so the refusal names
## the fix instead of hiding the item behind a silent skip.
##
## ## Every refusal is NAMED and reachable
##
## A teardown that silently does nothing is indistinguishable from a broken
## button, and a caller cannot tell the player which of the nine reasons applies.
## Each reason below is a concrete input state, and each has its own test.
##
## ## How the refusals are decided without a module edge
##
## `items` may not depend on `socket` (socket already depends on items) or on
## `set_bonus`. Every check therefore reads data `items` OWNS or a state key
## spelled as a plain id:
##
##  - a unique is `def.tags.has("unique")` — the authored identity, not the module
##    that happens to read it ([UniqueItem] reaches the same answer).
##  - a set member is a `set:<id>` tag on the definition.
##  - a socketed gem and a bound enchantment live in `actor.module_data["socket_state"]`,
##    read here by its plain id — the same way `ItemsApi` reads `item_state`, and
##    the same plain-id pattern `set_bonus` uses for `items`.
##
## ## Transactional
##
## Every guard runs before anything mutates, and the payout is proved on an
## [method Inventory.snapshot] before the instance is removed — the same
## plan-then-commit shape [method Crafting.craft_with] uses. A refused teardown
## changes nothing, and the bag never holds half a trade.
##
## ## Loop guards
##
## **This file contains no `while` loop and no recursion.** Every iteration is a
## `for` over an array already materialised at loop entry (`Equipment.SLOTS`, a
## definition's `tags`, a realized instance's `rolled`, a ledger parent's `slots`),
## and none of them appends to the array it walks — so there is no bound to take
## and nothing that can grow. The snapshot probe is a single `add` call, already
## bounded by `Inventory.capacity`.

# --- Refusal vocabulary -------------------------------------------------------
# Owned here so a panel can switch on a stable id. Each is a concrete input state.

## The actor is null.
const REASON_NO_ACTOR := "no_actor"
## The actor carries no inventory component, so it owns nothing to break down.
const REASON_NO_INVENTORY := "no_inventory"
## No carried instance carries this `instance_id`.
const REASON_UNKNOWN_INSTANCE := "unknown_instance"
## The instance is carried but its definition does not resolve.
const REASON_UNKNOWN_DEFINITION := "unknown_definition"
## The definition is not equipment at all.
const REASON_NOT_EQUIPMENT := "not_equipment"
## Equipment the authored slot rule puts in no wearable slot — a socket payload.
## Teardown is for the pieces that COMPETE for a slot, and a gem competes for none.
const REASON_UNWEARABLE := "unwearable_subtype"
## The piece is worn. Unequip it first; this refusal exists to name that.
const REASON_EQUIPPED := "equipped"
## A unique is a stable authored identity with a locked signature and a declared
## boss route. It is not inventory to be broken down.
const REASON_UNIQUE := "unique"
## A set member. Four of them are a tiered bonus; destroying one destroys progress.
const REASON_SET_MEMBER := "set_member"
## A socketed gem is stored in the socket ledger keyed by its HOST, not in the
## bag — so breaking the host down would orphan the gem with nothing able to reach
## it. Extraction first, via `SocketApi.extract_socket`.
const REASON_SOCKETED := "socketed"
## The enchantment channel is bound to this instance and dies with it.
const REASON_ENCHANTED := "enchanted"
## The grade's salvage material does not resolve. A CONTENT defect: the teardown
## refuses loudly rather than consuming the item and granting nothing.
const REASON_UNKNOWN_MATERIAL := "unknown_material"

# --- Identity tags, read straight off the authored definition ------------------

## Tag every unique definition carries — identity is data, not a subclass.
const UNIQUE_TAG := &"unique"
## `tags` entry naming the set a member belongs to: `set:<set_id>`.
const SET_TAG_PREFIX := "set:"

## Plain id of the socket ledger payload in `actor.module_data`. Spelled as a
## string rather than as a `SocketApi` reference because `items` may not depend on
## `socket`; this is the plain-id pattern, not an undeclared edge.
const SOCKET_STATE_KEY := &"socket_state"


## Tear down the carried instance `instance_id` and pay its materials.
##
## Returns `{ok, reason, instance_id, def_id, material_id, units, grade}`.
## `reason` is `""` on success. Every refusal leaves the inventory byte-identical
## to how it was found.
static func tear_down(actor: Actor, instance_id: StringName) -> Dictionary:
	var refusal := _refusal(actor, instance_id)
	if not refusal.is_empty():
		return _refuse(refusal, instance_id)
	var inventory := ItemsApi.inventory(actor)
	var instance := inventory.find_by_instance_id(instance_id)
	var def := _definition_of(inventory, instance)
	var material := TeardownYield.material_for(def.grade)
	var units := TeardownYield.units_for(def, instance)
	# Plan on a copy first: a yielded material that cannot fit must never cost the
	# player the piece. `snapshot` rebuilds every element, so removing from the
	# probe cannot mutate the live bag.
	var probe := inventory.snapshot()
	probe.remove_instance(instance_id)
	if probe.add(_material_def(material), units) > 0:
		return _refuse(REASON_UNKNOWN_MATERIAL, instance_id, def, material, units)
	# Commit: the item leaves, the material arrives. Nothing between these two
	# lines can fail, because everything that could was decided above.
	inventory.remove_instance(instance_id)
	inventory.add(_material_def(material), units)
	return {
		"ok": true,
		"reason": "",
		"instance_id": String(instance_id),
		"def_id": String(def.id),
		"material_id": String(material),
		"units": units,
		"grade": String(def.grade),
	}


## What this teardown WOULD pay, and why it would refuse. Changes nothing: no unit
## consumed, no state written. A screen renders its row from this.
static func preview(actor: Actor, instance_id: StringName) -> Dictionary:
	var refusal := _refusal(actor, instance_id)
	var inventory := ItemsApi.inventory(actor)
	var instance: ItemInstance = null
	if inventory != null:
		instance = inventory.find_by_instance_id(instance_id)
	var def := _definition_of(inventory, instance) if instance != null else null
	var quote := TeardownYield.quote(def, instance) if def != null else {"ok": false, "material_id": "", "units": 0, "grade": ""}
	return {
		"ok": refusal.is_empty(),
		"reason": refusal,
		"instance_id": String(instance_id),
		"def_id": String(def.id) if def != null else "",
		"material_id": String(quote.get("material_id", "")),
		"units": int(quote.get("units", 0)),
		"grade": String(quote.get("grade", "")),
		"rarity": String(quote.get("rarity", "")),
		"rolled_options": int(quote.get("rolled_options", 0)),
	}


## Every refusal reason this class can return, for a screen's vocabulary.
static func refusal_reasons() -> Array[String]:
	return [
		REASON_NO_ACTOR,
		REASON_NO_INVENTORY,
		REASON_UNKNOWN_INSTANCE,
		REASON_UNKNOWN_DEFINITION,
		REASON_NOT_EQUIPMENT,
		REASON_UNWEARABLE,
		REASON_EQUIPPED,
		REASON_UNIQUE,
		REASON_SET_MEMBER,
		REASON_SOCKETED,
		REASON_ENCHANTED,
		REASON_UNKNOWN_MATERIAL,
	]


## ## Why the guards are ordered the way they are
##
## Well-formedness first, because every later check dereferences the definition a
## well-formedness refusal may have refused to produce. Then identity — a unique
## or a set member is refused before an attachment is read, because those pieces
## are refused outright rather than for what they happen to carry. Then
## attachments, which are the only checks that read another module's state.
static func _refusal(actor: Actor, instance_id: StringName) -> String:
	if actor == null:
		return REASON_NO_ACTOR
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return REASON_NO_INVENTORY
	var instance := inventory.find_by_instance_id(instance_id)
	if instance == null:
		return REASON_UNKNOWN_INSTANCE
	var def := _definition_of(inventory, instance)
	if def == null:
		return REASON_UNKNOWN_DEFINITION
	if not def.is_equipment():
		return REASON_NOT_EQUIPMENT
	if not ItemSlots.is_wearable(def.subcategory):
		return REASON_UNWEARABLE
	if TeardownYield.material_for(def.grade) == &"":
		return REASON_UNKNOWN_MATERIAL
	if _is_worn(actor, instance_id):
		return REASON_EQUIPPED
	if is_unique(def):
		return REASON_UNIQUE
	if set_id_of(def) != &"":
		return REASON_SET_MEMBER
	var attached := _attachment_refusal(actor, instance_id)
	if not attached.is_empty():
		return attached
	return ""


## Whether this definition is a unique — the same authored tag [UniqueItem] reads,
## reached here without the module edge.
static func is_unique(def: ItemDef) -> bool:
	return def != null and def.tags.has(UNIQUE_TAG)


## The set this definition is a member of, or `&""` when it is a member of none.
static func set_id_of(def: ItemDef) -> StringName:
	if def == null:
		return &""
	for tag in def.tags:
		var text := String(tag)
		if text.begins_with(SET_TAG_PREFIX):
			return StringName(text.substr(SET_TAG_PREFIX.length()))
	return &""


## Every instance id `actor` currently wears, in worn order. The caller checks
## membership; returning the ids rather than a boolean keeps one traversal.
static func worn_instance_ids(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var equipment := ItemsApi.equipment(actor)
	if equipment == null:
		return out
	for slot in Equipment.SLOTS:
		var instance := equipment.equipped(slot)
		if instance != null:
			out.append(instance.instance_id)
	return out


## Whether this piece carries a socketed gem or a bound enchantment, and which.
## Reads the socket payload by its plain id: a `parents` entry keyed by this
## instance with a non-empty `gem`, or a `channels` entry keyed by this instance.
static func _attachment_refusal(actor: Actor, instance_id: StringName) -> String:
	var payload: Variant = actor.get_module_data(SOCKET_STATE_KEY)
	if not payload is Dictionary:
		return ""
	var state: Dictionary = payload
	var key := String(instance_id)
	var parents: Variant = state.get("parents", {})
	if parents is Dictionary:
		var entry: Variant = (parents as Dictionary).get(key, {})
		if entry is Dictionary:
			for slot_entry in (entry as Dictionary).get("slots", []):
				# `slots` is a fixed stored array: this reads each entry's `gem` and
				# appends nothing, so there is no bound to take.
				if slot_entry is Dictionary and not (slot_entry as Dictionary).get("gem", {}).is_empty():
					return REASON_SOCKETED
	var channels: Variant = state.get("channels", {})
	if channels is Dictionary and (channels as Dictionary).has(key):
		return REASON_ENCHANTED
	return ""


static func _is_worn(actor: Actor, instance_id: StringName) -> bool:
	return worn_instance_ids(actor).has(instance_id)


static func _definition_of(inventory: Inventory, instance: ItemInstance) -> ItemDef:
	if instance == null:
		return null
	if instance.def_ref != null:
		return instance.def_ref
	return inventory.definition_of(instance.def_id)


static func _material_def(material_id: StringName) -> ItemDef:
	return Crafting.resolve(material_id)


static func _refuse(
	reason: String,
	instance_id: StringName,
	def: ItemDef = null,
	material_id: StringName = &"",
	units: int = 0
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"instance_id": String(instance_id),
		"def_id": String(def.id) if def != null else "",
		"material_id": String(material_id),
		"units": units,
		"grade": String(def.grade) if def != null else "",
	}