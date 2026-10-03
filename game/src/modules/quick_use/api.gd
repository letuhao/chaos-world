class_name QuickUseApi
extends RefCounted

## Public facade for the `quick_use` module. Other modules and `ui/` may reference
## ONLY this file (`api.gd`).
##
## A quick-use bar is a **binding** plus one verb: which item id sits in which of the
## six slots, and the verb that spends one. It is not a second inventory — `items`
## owns quantities, stacks and effects, and every fact this facade reports about an
## item is read through [ItemsApi] rather than kept here.
##
## ADR 0056 put a runtime per-actor system in a module and left `app/` to wire it,
## which is the move DEF-0098 recorded as owed for the retired prototype's slot
## table. That prototype's id-persistence model is kept verbatim: a save stores six
## bare `StringName`s, never a serialized definition.
##
## The surface is five methods because that is all a bar is. There is no `quantity`
## to set and nothing to inspect per slot beyond [method summary]; a caller that
## wants to know what an actor carries is asking `items`.

## The component this facade owns, reached through the facade and nowhere else.
const SLOTS_COMPONENT := &"quick_use_slots"

## Where the module persists, under its own key so core never interprets it.
const STATE_KEY := &"quick_use_slots"

## The bar's width, published for a panel that lays slots out before it has data.
const SLOT_COUNT := QuickUseSlots.SLOT_COUNT


## Attach the bar to `actor`, adopting whatever a prior `Actor.from_dict` carried
## under [constant STATE_KEY]. Idempotent and safe after a load: a restored snapshot
## is the starting state, not a second copy of it.
static func attach(actor: Actor) -> void:
	if actor == null or actor.component(SLOTS_COMPONENT) is QuickUseSlots:
		return
	var payload: Dictionary = actor.get_module_data(STATE_KEY)
	actor.set_component(SLOTS_COMPONENT, QuickUseSlots.new(payload.get("slots", [])))
	# Re-write the adopted payload, so the key on the actor holds the module's own
	# normalized shape rather than whatever the save happened to carry.
	_persist(actor, actor.component(SLOTS_COMPONENT) as QuickUseSlots)


## Bind `def_id` to `slot_index`, replacing whatever was there. The binding is a
## pointer, not a copy: this moves nothing into the bag and nothing out of it.
##
## NOT gated on the actor carrying the item. A bar is allowed to name a pill the
## player has not picked up yet, and the slot empties itself on the first spend once
## the stack is gone. Adding a carry gate here would be a new rule, not this move.
static func assign_slot(actor: Actor, slot_index: int, def_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if not _in_range(slot_index):
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	if def_id == &"":
		return {"ok": false, "reason": "invalid_item"}
	var slots := _slots(actor)
	slots.bind(slot_index, def_id)
	_persist(actor, slots)
	return {"ok": true, "slot": slot_index, "def_id": String(def_id)}


## Release `slot_index` and report the id it held. Free and non-destructive: the item
## is still in the bag, which is the whole difference between a bar and an inventory.
static func clear_slot(actor: Actor, slot_index: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if not _in_range(slot_index):
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	var slots := _slots(actor)
	var previous := slots.release(slot_index)
	_persist(actor, slots)
	return {"ok": true, "slot": slot_index, "prev_def_id": String(previous)}


## Spend the item bound to `slot_index`, delegating the whole effect to `items`.
##
## `ItemsApi.use_item` is all-or-nothing, so a refused spend costs nothing and the
## binding survives it. A stack that empties releases its own slot: a bar entry
## pointing at nothing can never fire again, and whether the last one is gone is
## `items`' fact to answer, not this module's to re-derive.
static func use_slot(actor: Actor, slot_index: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if not _in_range(slot_index):
		return {"ok": false, "reason": "invalid_slot", "slot": slot_index}
	var slots := _slots(actor)
	var def_id := slots.bound_at(slot_index)
	if def_id == &"":
		return {"ok": false, "reason": "empty_slot", "slot": slot_index}
	var result: Dictionary = ItemsApi.use_item(actor, def_id, 1)
	if bool(result.get("ok", false)) and not ItemsApi.has_item(actor, def_id, 1):
		slots.release(slot_index)
		_persist(actor, slots)
	return result


## Everything a quick-use panel needs to draw the bar: primitives only, so it can be
## a `summary()` payload unchanged. `{}` when there is no actor.
##
## The `quantity` on each row is read from the bag at call time and is not this
## module's to remember — which is why it tracks the inventory instead of drifting
## from it. A row with no actor-side inventory reads `0` rather than raising.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var slots := _slots(actor)
	var rows: Array = []
	for index in SLOT_COUNT:
		var def_id := slots.bound_at(index)
		var quantity := 0
		if def_id != &"":
			var inv := ItemsApi.inventory(actor)
			if inv != null:
				quantity = inv.count(def_id)
		rows.append({"index": index, "def_id": String(def_id), "quantity": quantity})
	return {"slot_count": SLOT_COUNT, "slots": rows}


# --- Internals -------------------------------------------------------------


static func _slots(actor: Actor) -> QuickUseSlots:
	if actor == null:
		return null
	var existing := actor.component(SLOTS_COMPONENT) as QuickUseSlots
	if existing != null:
		return existing
	attach(actor)
	return actor.component(SLOTS_COMPONENT) as QuickUseSlots


static func _in_range(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT


static func _persist(actor: Actor, slots: QuickUseSlots) -> void:
	if actor == null or slots == null:
		return
	actor.set_module_data(STATE_KEY, {"slots": slots.to_ids()})
