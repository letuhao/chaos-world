class_name ItemsApi
extends RefCounted

## Public facade for the `items` module (ADR 0007). Owns inventory, equipment,
## the use/generation entry points, and item-state serialization so core never
## references concrete item types (ADR 0027).

const INVENTORY_COMPONENT := &"inventory"
const EQUIPMENT_COMPONENT := &"equipment"
const DEFAULT_CAPACITY := 24


static func attach(actor: Actor, capacity: int = DEFAULT_CAPACITY) -> void:
	actor.set_component(INVENTORY_COMPONENT, Inventory.new(capacity))
	actor.set_component(EQUIPMENT_COMPONENT, Equipment.new())
	# Register the item-state serialization hook (ADR 0027).
	actor.set_item_state_serializer(func(a: Actor) -> Dictionary: return serialize(a))
	# Restore item state captured by a prior from_dict (ADR 0027); never rerolls.
	var pending: Dictionary = actor.get_module_data(&"item_state")
	actor.set_module_data(&"item_state", {})
	if not pending.is_empty():
		deserialize(actor, pending)


static func inventory(actor: Actor) -> Inventory:
	return actor.component(INVENTORY_COMPONENT)


static func equipment(actor: Actor) -> Equipment:
	return actor.component(EQUIPMENT_COMPONENT)


static func craft(recipe: RecipeDef, inventory: Inventory) -> bool:
	var crafting := Crafting.new(recipe.station)
	return crafting.craft(recipe, inventory)


## Whether the actor's inventory holds at least `quantity` of `def_id`.
static func has_item(actor: Actor, def_id: StringName, quantity: int = 1) -> bool:
	var inv := inventory(actor)
	return inv != null and inv.has(def_id, quantity)


## Remove `quantity` of `def_id` from the actor's inventory. All-or-nothing:
## returns false and changes nothing when the stack is short.
static func consume_item(actor: Actor, def_id: StringName, quantity: int = 1) -> bool:
	var inv := inventory(actor)
	if inv == null or not inv.has(def_id, quantity):
		return false
	return inv.remove(def_id, quantity) == quantity


## Equip a non-stackable `def` from the actor's inventory into `slot`. The
## instance is removed from inventory and equipped atomically; an invalid equip
## changes nothing and leaves the existing item in inventory (ADR 0026).
static func equip_item(actor: Actor, slot: StringName, def: ItemDef) -> bool:
	var inv := inventory(actor)
	var eq := equipment(actor)
	if inv == null or eq == null or def == null:
		return false
	var instance := inv.find_instance(def.id)
	if instance == null:
		return false
	# Validate before removing so a rejected equip leaves inventory intact.
	var current := eq.equipped(slot)
	var current_def := eq.definition(slot)
	if not inv.remove_instance(instance.instance_id):
		return false
	if not eq.equip(actor, slot, def, instance):
		inv.add_instance(instance)
		return false
	if current != null:
		# `add_instance` returns LEFTOVER, not success: 0 means it all fitted. `not 0`
		# is true, so the old `if not inv.add_instance(current)` took this rollback
		# branch on every successful replacement and undid a swap that had worked —
		# which reads to a caller as "equip failed" and to a test as a slot that will
		# not re-equip. Compare against 0, as `unequip_to_inventory` already does.
		if inv.add_instance(current) != 0:
			# The replaced item has nowhere to go: restore everything.
			eq.unequip(actor, slot)
			inv.add_instance(instance)
			if current_def != null:
				eq.equip(actor, slot, current_def, current)
			inv.add_instance(current)
			return false
	return true


## Unequip `slot` back into the inventory, preserving the instance. Returns
## false (changing nothing) when the slot is empty or inventory is full.
static func unequip_to_inventory(actor: Actor, slot: StringName) -> bool:
	var eq := equipment(actor)
	var def := eq.definition(slot)
	if def == null:
		return false
	var inv := inventory(actor)
	if inv == null or inv.is_full():
		return false
	var instance := eq.unequip(actor, slot)
	if instance == null:
		return false
	if inv.add_instance(instance) != 0:
		eq.equip(actor, slot, def, instance)
		return false
	return true


## Realize `def` from a seeded roll and acquire it into the actor's inventory.
## The realized effects, rarity and realm travel on the returned instance, so a
## caller never has to know how an item becomes owned (ADR 0025). Returns null
## when the inventory is full; nothing is consumed or rolled away.
static func generate(actor: Actor, def: ItemDef, seed_value: int) -> ItemInstance:
	var inv := inventory(actor)
	if inv == null or def == null or inv.is_full():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var instance_id := &"%s_%d" % [def.id, inv.next_instance_id()]
	var instance := ItemGenerator.generate(def, instance_id, rng)
	instance.def_ref = def
	if def.stackable:
		var batch := ItemStack.from_instance(instance, 1)
		batch.def_ref = def
		if inv.add_batch(batch) != 0:
			return null
	else:
		if inv.add_instance(instance) != 0:
			return null
	return instance


## Use (consume/learn/property) one unit of `def_id`. All-or-nothing: consumes
## nothing and changes nothing when the item is absent or has no usable effect.
static func use_item(actor: Actor, def_id: StringName, quantity: int = 1) -> Dictionary:
	var inv := inventory(actor)
	if inv == null or quantity <= 0 or not inv.has(def_id, quantity):
		return {"ok": false, "reason": "not_carried"}
	var def := inv.definition_of(def_id)
	if def == null:
		def = Crafting.resolve(def_id)
	if def == null:
		return {"ok": false, "reason": "unknown_definition"}
	var result := ItemUse.apply(actor, def, inv.sample(def_id))
	if not bool(result.get("ok", false)):
		return result
	inv.remove(def_id, quantity)
	return result


## Serialize the actor's item state (inventory + equipment) into a versioned,
## plain dictionary (ADR 0027).
static func serialize(actor: Actor) -> Dictionary:
	var inv := inventory(actor)
	var eq := equipment(actor)
	var stacks: Array = []
	var instances: Array = []
	if inv != null:
		for stack in inv.stacks():
			stacks.append(stack.to_dict())
		for instance in inv.instances():
			instances.append(instance.to_dict())
	var slots: Dictionary = {}
	if eq != null:
		for slot in eq.all():
			slots[slot] = {
				"instance": eq.equipped(slot).to_dict(),
				"def_id": String(eq.equipped(slot).def_id),
			}
	return {
		"version": 2,
		"inventory": {"stacks": stacks, "instances": instances},
		"equipment": slots,
	}


## Restore item state from a serialized dictionary. This *replaces* the actor's
## item state: existing stacks, instances and equipped items are cleared first,
## so loading a save can never duplicate loot or double-equip. Realized values
## are restored exactly as saved and never rerolled (ADR 0027).
static func deserialize(actor: Actor, data: Dictionary) -> void:
	if data.is_empty():
		return
	var inv := inventory(actor)
	var eq := equipment(actor)
	if inv == null or eq == null:
		return
	for slot in Equipment.SLOTS:
		if eq.equipped(slot) != null:
			eq.unequip(actor, slot)
	inv.clear()
	var inv_data: Dictionary = data.get("inventory", {})
	for stack_data in inv_data.get("stacks", []):
		var def := _resolve_def(inv, StringName(stack_data.get("def_id", "")))
		if def != null:
			inv.add(def, int(stack_data.get("quantity", 0)))
	for instance_data in inv_data.get("instances", []):
		var instance := ItemInstance.from_dict(ItemInstance.migrate(instance_data))
		instance.def_ref = _resolve_def(inv, instance.def_id)
		inv.add_instance(instance)
	for slot in data.get("equipment", {}).keys():
		var entry: Dictionary = data["equipment"][slot]
		var instance_data: Dictionary = entry.get("instance", entry)
		var instance := ItemInstance.from_dict(ItemInstance.migrate(instance_data))
		var def := _resolve_def(inv, instance.def_id)
		if def != null:
			eq.equip(actor, StringName(slot), def, instance)


## Prefer the definition the inventory already knows, so an in-memory definition
## with authored values wins over a content-tree re-read.
static func _resolve_def(inv: Inventory, def_id: StringName) -> ItemDef:
	var known := inv.definition_of(def_id)
	return known if known != null else Crafting.resolve(def_id)
