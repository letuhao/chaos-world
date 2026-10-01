class_name ItemsApi
extends RefCounted

## Public facade for the `items` module (ADR 0007).

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
## instance is removed from inventory and equipped atomically; returns false
## (changing nothing) when the item is absent from inventory.
static func equip_item(actor: Actor, slot: StringName, def: ItemDef) -> bool:
	var inv := inventory(actor)
	if inv == null:
		return false
	var instance := inv.find_instance(def.id)
	if instance == null:
		return false
	if not inv.remove_instance(instance.instance_id):
		return false
	return equipment(actor).equip(actor, slot, def, instance)


## Unequip `slot` back into the inventory, preserving the instance. Returns
## false (changing nothing) when the slot is empty or inventory is full.
static func unequip_to_inventory(actor: Actor, slot: StringName) -> bool:
	var instance := equipment(actor).unequip(actor, slot)
	if instance == null:
		return false
	return inventory(actor).add_instance(instance) == 0


## Serialize the actor's item state (inventory + equipment) into a versioned,
## plain dictionary. Owns all item-state serialization so core never references
## concrete item types (ADR 0027).
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
			slots[slot] = eq.equipped(slot).to_dict()
	return {
		"version": 1,
		"inventory": {"stacks": stacks, "instances": instances},
		"equipment": slots,
	}


## Restore item state from a serialized dictionary. Restores instances and
## re-applies equipment definition modifiers; never rerolls (ADR 0027).
static func deserialize(actor: Actor, data: Dictionary) -> void:
	if data.is_empty():
		return
	var inv := inventory(actor)
	var eq := equipment(actor)
	if inv == null or eq == null:
		return
	var inv_data: Dictionary = data.get("inventory", {})
	for stack_data in inv_data.get("stacks", []):
		var def := Crafting.load_item(StringName(stack_data.get("def_id", "")))
		if def != null:
			inv.add(def, int(stack_data.get("quantity", 0)))
	for instance_data in inv_data.get("instances", []):
		inv.add_instance(ItemInstance.from_dict(instance_data))
	for slot in data.get("equipment", {}):
		var instance: ItemInstance = ItemInstance.from_dict(data["equipment"][slot])
		var def := Crafting.load_item(instance.def_id)
		if def != null:
			eq.equip(actor, StringName(slot), def, instance)
