class_name MapGatherAction
extends RefCounted

## Hand a harvested map node's yield to an actor's inventory. `Crafting.resolve`
## is `items` internals that only `app/` may name (the shop_counter.gd
## precedent), and `Inventory.add` returns the leftover a full bag refused, so
## the answer names what actually landed rather than what was promised.
## A yield id the content tree does not define is skipped and reported in
## `unknown`: a harvest that silently grants nothing is indistinguishable from
## a broken one.


static func deliver(actor: Actor, harvest: Dictionary) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "gained": {}, "unknown": []}
	if harvest.is_empty():
		return {"ok": false, "reason": "nothing_here", "gained": {}, "unknown": []}
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor)
	var inventory := ItemsApi.inventory(actor)
	var gained := {}
	var unknown: Array = []
	for key in harvest.keys():
		var def := Crafting.resolve(StringName(String(key)))
		var quantity := maxi(0, int(harvest[key]))
		if def == null or quantity <= 0:
			unknown.append(String(key))
			continue
		var refused := inventory.add(def, quantity)
		var taken := quantity - refused
		if taken > 0:
			gained[String(key)] = taken
	if gained.is_empty():
		return {
			"ok": false,
			"reason": "unknown_yield" if unknown.size() > 0 else "inventory_full",
			"gained": gained,
			"unknown": unknown,
		}
	return {"ok": true, "reason": "", "gained": gained, "unknown": unknown}
