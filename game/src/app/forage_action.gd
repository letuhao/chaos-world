class_name ForageAction
extends RefCounted

## The composition root's harvest entry point: the ONE place under `game/src` that turns
## "a player chose to work this node" into a [method ForageApi.harvest] call.
##
## ## Why this file exists rather than a screen calling `ForageApi.harvest` directly
##
## Two reasons, and both of them are about honesty rather than layering.
##
## **First, the route gate.** `tools/data.py`'s `Route.call_sites` is how `data audit`
## decides a route is shipping rather than declared: the verb has to be invoked from a
## `.gd` under `game/src`, and `game/tests` is excluded by construction because a call site
## only a test makes is not a delivery path. A `forage` module nothing outside itself calls
## is the exact shape `quest` is in, and it is a module whose verbs exist, whose tests
## pass, and whose call graph reaches nothing. This file is that call site.
##
## **Second, the owner ref.** `accrue` compares the caller-supplied `owner` against the
## ledger's holder, so somebody has to know that a player pressing "harvest" on the node
## they hold means `{"kind":"actor","id":<actor id>}`. That derivation is a composition
## concern — it is the join between "an actor" and "an `OwnerRef`" — and burying it in a
## screen would mean every screen spelled it slightly differently.
##
## ## It dispatches and counts. It does not decide.
##
## Every refusal is whatever `ForageApi.harvest` returned, passed through by name. This
## file owns no gate, computes no yield, charges no upkeep and holds no roster — the
## `InstitutionResolver` shape, and the `app_state_warnings` rule in `tools/arch/enforce.py`
## is satisfied structurally: no persistence, no tick, no member table.
##
## ## Periods come from the caller, always
##
## `periods` is required and never defaulted. There is no clock in this program that a
## harvest may consult (DEF-0111); the player pressing a button says *how long* they worked,
## and a defaulted period would be an invented tick wearing a button's clothes.

## The owner ref a player-authored harvest carries. An `actor` holder is the only kind a
## single player can be; whether a kind is real is the resolver's answer (ADR 0933).
const OWNER_KIND := "actor"


## Work `node_id` for `periods` on `actor`'s behalf, and return the harvest's own answer.
##
## `{ok, reason, node_id, item_id, periods, yielded, granted, accrued, condition}`, with
## every key always present — a caller that switches on `reason` never has to test for a
## missing field, which is what makes the refusal vocabulary a real contract.
static func gather(actor: Actor, node_id: StringName, periods: int) -> Dictionary:
	if actor == null:
		return _no_actor()
	return ForageApi.harvest(actor, node_id, owner_ref(actor), periods)


## The `OwnerRef` dictionary this actor is recorded under, as `accrue` compares it.
##
## Read from the actor rather than passed in, because a caller that could pass its own
## `owner` could work a node belonging to someone else by naming their id — which is a
## custody bug, not a convenience. The actor IS the owner; the ref is a rendering of that.
static func owner_ref(actor: Actor) -> Dictionary:
	return {"kind": OWNER_KIND, "id": String(actor.id)}


## Whether `actor` may work `node_id` at all, without accruing anything.
##
## The question a panel binds a button's enabled state to, asked here rather than by a
## screen restating `permits` and the holder check — a screen that re-derives the gate is a
## second copy of the rule that can drift from the first.
static func workable(actor: Actor, node_id: StringName) -> bool:
	if actor == null:
		return false
	var node := ResourceNodeCatalog.instance().definition(node_id)
	if node == null or not ForageApi.has_granter():
		return false
	if not node.permits(actor.realm()):
		return false
	var summary := HoldingsApi.summary(actor)
	var nodes: Dictionary = summary.get("nodes", {}) as Dictionary
	if not nodes.has(String(node_id)):
		return false
	var entry: Dictionary = nodes[String(node_id)]
	var owner: Dictionary = entry.get("owner", {}) as Dictionary
	return String(owner.get("id", "")) == String(actor.id)


static func _no_actor() -> Dictionary:
	return {
		"ok": false,
		"reason": ForageApi.NO_ACTOR,
		"node_id": "",
		"item_id": "",
		"periods": 0,
		"yielded": 0,
		"granted": 0,
		"accrued": 0,
		"condition": 0,
	}
