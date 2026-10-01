class_name ItemsApi
extends RefCounted

## Public facade for the `items` module (ADR 0007).

const INVENTORY_COMPONENT := &"inventory"
const EQUIPMENT_COMPONENT := &"equipment"
const DEFAULT_CAPACITY := 24


static func attach(actor: Actor, capacity: int = DEFAULT_CAPACITY) -> void:
	actor.set_component(INVENTORY_COMPONENT, Inventory.new(capacity))
	actor.set_component(EQUIPMENT_COMPONENT, Equipment.new())


static func inventory(actor: Actor) -> Inventory:
	return actor.component(INVENTORY_COMPONENT)


static func equipment(actor: Actor) -> Equipment:
	return actor.component(EQUIPMENT_COMPONENT)


static func craft(recipe: RecipeDef, inventory: Inventory) -> bool:
	var crafting := Crafting.new(recipe.station)
	return crafting.craft(recipe, inventory)
