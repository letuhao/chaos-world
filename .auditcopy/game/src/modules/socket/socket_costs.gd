class_name SocketCosts
extends RefCounted

## The cost side of every socket transaction, expressed as a crafting cost.
##
## There is one cost implementation in the game and it belongs to the items
## module: a `Crafting` station run against the actor's `Inventory`. A socket
## transaction therefore does not remove units itself — it hands its reagents to
## the same all-or-nothing cost path `ItemsApi.craft` uses, so "validate, then
## consume" cannot diverge between crafting and socketing.

## Station the socket cost transaction runs at. A synthesized recipe carries no
## outputs: the product of a socket transaction is state on an item, not an item.
const STATION := &"socket"


## Spend `reagent_ids`, one unit each, from `inventory`. All-or-nothing: returns
## a non-OK error and consumes nothing when any unit is missing.
static func spend(inventory: Inventory, reagent_ids: Array[StringName]) -> Error:
	if inventory == null:
		return ERR_UNCONFIGURED
	if reagent_ids.is_empty():
		return ERR_INVALID_PARAMETER
	return Crafting.new(SocketCosts.STATION).craft_with(null, recipe_for(reagent_ids), inventory)


## The cost recipe for `reagent_ids`: every unit is an input, nothing is
## produced, and a deterministic id keeps the transaction traceable in logs.
static func recipe_for(reagent_ids: Array[StringName]) -> RecipeDef:
	var recipe := RecipeDef.new()
	recipe.id = &"socket_cost"
	recipe.display_name = "Socket cost"
	recipe.station = SocketCosts.STATION
	recipe.inputs = reagent_ids.duplicate()
	recipe.outputs = []
	return recipe


## Whether `inventory` can pay `reagent_ids` without being touched. Read by a
## preview and by every eligibility report, so "can I afford this" is asked the
## same way the transaction will answer it.
static func can_pay(inventory: Inventory, reagent_ids: Array[StringName]) -> bool:
	if inventory == null or reagent_ids.is_empty():
		return false
	for reagent_id in reagent_ids:
		if not inventory.has(reagent_id):
			return false
	return true
