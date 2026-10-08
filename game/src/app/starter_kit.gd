class_name StarterKit
extends RefCounted

## Hand a new body its authored starter kit, exactly once (BL-0904 / BL-0909).
##
## ## Why this lives in `app/`
##
## The kit is DATA the `destiny` module owns: `DestinyApi.starter_pack(actor)` resolves the
## authored default, or a pack a destiny this body holds has REGISTERED in its place (and
## the two never merge — `DestinyStarterPacks.resolve` returns one pack). Turning rows into
## real instances is the composition root's job, which is why `destiny` declares no `items`
## dependency for a feature about what a player starts holding.
##
## ## The once-guard is the WORLD LEDGER's, not a field here
##
## `app/` holds no ledger (`APP_STATE_MARKERS`), and a boolean on this static would be a
## second answer to "did this body already draw" that a save could not carry. The fact
## `starter_kit_drawn` in `WorldFact` is monotone and per-actor, so `count > 0` is the whole
## rule — the same "once is the ledger's" shape `WorldAmbient` and `EventState.paid` use.
## A restored body funnels through here again and draws nothing.
##
## ## Wearables are minted, stacks are added
##
## `ItemsApi.generate` realizes exactly ONE unit of a non-stackable def as an `ItemInstance`,
## which is what the workbench's bag-row builder lists and what `ItemActionRules`
## `equip_shape_reason` can match — both are INSTANCE lookups that cannot see a stack. A
## row asking for several units is a stack and goes through `Inventory.add` instead, because
## a loop of `generate` calls would spend one bag slot per unit and a 24-slot bag cannot
## hold 25 coins.

## The monotone fact that records the draw. Plain id, ADR 0113's own namespace rule.
const FACT := &"starter_kit_drawn"


## Give `actor` whatever pack it is owed, once.
##
## Returns `{ok, reason, already, pack_id, replaced, granted: [item_id], refused: [{id, reason}]}`.
## A body that already drew answers `already: true` and grants nothing; a row the bag cannot
## hold is refused BY NAME and the rest of the kit is still attempted, because a full bag
## must not silently drop the rows behind it.
static func grant(actor: Actor) -> Dictionary:
	if actor == null:
		return _answer(false, "no_actor", false, {}, [], [])
	if WorldFact.has(actor, FACT):
		return _answer(true, "", true, {}, [], [])
	var pack := DestinyApi.starter_pack(actor)
	var granted: Array[String] = []
	var refused: Array[Dictionary] = []
	for row in pack.get("entries", []) as Array:
		_deliver(actor, row as Dictionary, granted, refused)
	# The fact is written AFTER the delivery, so a refusal to fill the bag cannot mark the
	# draw as done and hand the player nothing on the next boot.
	WorldFact.record(actor, FACT, 1)
	return _answer(
		true,
		"",
		false,
		{
			"pack_id": String(pack.get("pack_id", "")),
			"replaced": bool(pack.get("replaced", false)),
			"destiny_id": String(pack.get("destiny_id", "")),
		},
		granted,
		refused
	)


## The read model: what the kit WOULD be, and whether it was drawn. Primitives only.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var pack := DestinyApi.starter_pack(actor)
	return {
		"has_actor": true,
		"drawn": WorldFact.has(actor, FACT),
		"pack_id": String(pack.get("pack_id", "")),
		"replaced": bool(pack.get("replaced", false)),
		"destiny_id": String(pack.get("destiny_id", "")),
		"rows": (pack.get("entries", []) as Array).size(),
	}


# --- internals ---------------------------------------------------------------


## Put one authored row into the bag, appending to `granted` or `refused`.
##
## **Inert on every refusal**: nothing is acquired unless the mint or the add succeeds, so a
## refused row cannot half-deliver.
static func _deliver(
	actor: Actor, row: Dictionary, granted: Array[String], refused: Array[Dictionary]
) -> void:
	var item_id := StringName(row.get("item_id", ""))
	var count := maxi(1, int(row.get("count", 1)))
	if item_id == &"":
		refused.append({"id": "", "reason": "row_names_no_item"})
		return
	var def := Crafting.resolve(item_id)
	if def == null:
		# A kit naming an item the tree does not define is a CONTENT bug, and it is reported
		# rather than skipped: the player was promised something that does not exist.
		refused.append({"id": String(item_id), "reason": "unknown_item"})
		return
	var inv := ItemsApi.inventory(actor)
	if inv == null:
		refused.append({"id": String(item_id), "reason": "no_inventory"})
		return
	if count > 1:
		if inv.add(def, count) != 0:
			refused.append({"id": String(item_id), "reason": "inventory_full"})
			return
		granted.append(String(item_id))
		return
	if inv.is_full():
		refused.append({"id": String(item_id), "reason": "inventory_full"})
		return
	# The seed is derived from the actor and the item, so one body always draws the same
	# realization of its kit — the same determinism rule every delivery path here holds
	# (ADR 0025: no path reads an unseeded RNG).
	if ItemsApi.generate(actor, def, _seed(actor, item_id)) == null:
		refused.append({"id": String(item_id), "reason": "inventory_full"})
		return
	granted.append(String(item_id))


static func _seed(actor: Actor, item_id: StringName) -> int:
	return hash("starter:%s:%s" % [String(actor.id), String(item_id)])


static func _answer(
	ok: bool,
	reason: String,
	already: bool,
	pack: Dictionary,
	granted: Array[String],
	refused: Array[Dictionary]
) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"already": already,
		"pack_id": String(pack.get("pack_id", "")),
		"replaced": bool(pack.get("replaced", false)),
		"destiny_id": String(pack.get("destiny_id", "")),
		"granted": granted,
		"refused": refused,
	}
