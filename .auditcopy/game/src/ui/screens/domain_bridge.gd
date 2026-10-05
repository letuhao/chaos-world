class_name DomainBridge
extends RefCounted

## The injected view of the `domain` module for the UI program, and the SEAM that keeps
## the domain surface reachable from a screen without breaking the boundary.
##
## ## Why a bridge exists at all
##
## `ui/` is a pure consumer (`AGENTS.md`, `tools/arch/rules.py`): a screen may reach a
## gameplay module only through that module's facade (`api.gd`), and only for the modules
## listed in `rules.UI_MODULES`. Two facts close every other door here:
##
##  - `domain` is NOT in `rules.UI_MODULES`, so even `DomainApi` would be refused;
##  - `app/` is a PRIVATE unit (`rules.PRIVATE_UNITS`), so a screen naming `DomainBoot`
##    — the composition root's own wiring — is refused a second time.
##
## So a screen had exactly two legal futures: render a domain nothing can enter, or
## reach through a seam. This is the seam, and it is the shape ADR 0143 already settled
## for the loot and world surfaces: the composition root hands over plain `Callable`s
## (`DomainBoot.bridge()`) and every module type stays on the `app/` side. The screen
## therefore names NO domain type at all — not `DomainApi`, not `DomainMinimap`, not
## `DomainMap` — and the domain module never learns the UI exists.
##
## ## Why the fixture verbs are HERE and not a thirteenth facade method
##
## `DomainFixtures` has three verbs (`arm` / `attempt` / `claim`) and `DomainApi` is at
## its hard twelve-method cap with a docblock saying a UI need must be published inside
## an existing read model rather than appended. So the fixtures are reached the same way
## the map is: `app/` forwards to them and this bridge carries the callables. The cap is
## respected by construction rather than by restraint.
##
## Every callable answers primitives only, and an unwired callable reads as "not
## available" rather than as a failure — which is how a screen disables an action
## instead of pretending it worked.

## The stable seed this program's own buttons use. A SEED, not a roll: the screen
## generates a domain, so two runs of the same button should be the same domain, and a
## random seed would make "what is in there" unreadable between two visits.
const DEFAULT_SEED := 20260904

## What every verb is allowed to refuse with, as the reason ids the domain module
## publishes. The screen's own vocabulary is this table, NOT a wording invented here.
const REASON_TEXT := {
	# DomainApi
	"no_actor": "No hero is bound to this screen",
	"no_map": "No domain is active",
	"no_active_domain": "No domain is active",
	"unknown_room": "That room is not in this domain",
	"invalid_contract": "This domain's map is broken and cannot be entered",
	"no_such_template": "No such domain is authored",
	"generation_refused": "That domain could not be generated from its seed",
	# DomainFixtures
	"unknown_fixture": "That fixture is not in this room",
	"unknown_fixture_kind": "That fixture declares a kind this build cannot run",
	"wrong_kind_for_this_verb": "That fixture does not answer this action",
	"already_fired": "That trap has already fired this run",
	"already_claimed": "That is already claimed",
	"unknown_node": "That node is not part of this formation",
	"missing_key": "You are not carrying its key",
	"realm_below_the_floor": "Your realm is below the floor it demands",
	"no_inventory_bridge": "Rewards cannot be delivered — nothing is wired to give them",
	"inventory_full": "Your bag is full, so the claim was left untouched",
	"authors_no_status_id": "That trap authors no status, so it has nothing to fire",
	"authors_no_damage_share": "That trap authors no damage share",
	"authors_nothing_to_grant": "That fixture authors nothing to grant",
}

## `DomainApi.templates()` -> Array[Dictionary]: the authored domain catalogue, so a
## screen can list what exists without generating anything.
var list_templates: Callable
## `DomainBoot.read_model(actor)` -> Dictionary: what is authored, and what is active.
var read_active: Callable
## `DomainBoot.enter_domain(actor, template_id, seed_value)` -> Dictionary: the one
## production entry point into a domain.
var enter: Callable
## `DomainBoot.leave_domain(actor)` -> Dictionary: end the run, keep the discoveries.
var leave: Callable
## `DomainBoot.visit_room(actor, room_id, weather)` -> Dictionary: record a room reached.
var visit: Callable
## `DomainBoot.minimap(actor)` -> Dictionary: `DomainMinimap.render`, as primitives.
var minimap: Callable
## `DomainBoot.rooms(actor)` -> Array[Dictionary]: the room list, with kinds and tags.
var rooms: Callable
## `DomainFixtures.arm(actor, room_id, fixture_id, delta)` -> Dictionary: a trap's telegraph.
var arm_fixture: Callable
## `DomainFixtures.attempt(actor, room_id, fixture_id, node_id)` -> Dictionary: a puzzle node.
var attempt_fixture: Callable
## `DomainFixtures.claim(actor, room_id, fixture_id)` -> Dictionary: open a treasure.
var claim_fixture: Callable


## The player-facing sentence for a reason id. Falls back to the id itself, because a
## reason this build has no wording for must still be REPORTED rather than dropped —
## silently shortening a refusal to "Rejected" is how a player concludes the actor
## cannot do the thing at all.
func reason_text(reason: String) -> String:
	var text := String(REASON_TEXT.get(reason, reason))
	return reason if text.is_empty() else text


## Whether an action is wired. A screen reads this before it offers an action, so a
## domain program that was never bound disables the verbs rather than half-answering.
func has(action: StringName) -> bool:
	var callable: Callable = _callable_for(action)
	return callable.is_valid()


## Invoke `action` with `args`, returning an empty dictionary when the callable is
## not wired or does not answer a dictionary. A screen never null-checks the bridge.
##
## Two Godot-version facts, both learned the hard way here. `Callable.callv(args)` was
## REMOVED in 4.4 (this project is 4.7), so calling it raised "Nonexistent function
## 'callv'" on every press and every answer read as empty. GDScript also has NO `*args`
## spread syntax — that is a parse error, not a runtime one. The supported forward is
## `Callable.call.bindv(args).call()`.
func call_action(action: StringName, args: Array = []) -> Dictionary:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return {}
	var result: Variant = callable.bindv(args).call()
	return result as Dictionary if result is Dictionary else {}


## As [method call_action], for the two verbs whose answer is an array rather than a
## dictionary (`list_templates`, `rooms`). Empty when unwired or of the wrong shape.
func call_list(action: StringName, args: Array = []) -> Array:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return []
	var result: Variant = callable.bindv(args).call()
	return result as Array if result is Array else []


## Everything this bridge can reach, as primitives, so a screen or a test can assert the
## wiring ITSELF rather than inferring it from a verb that quietly did nothing.
func summary() -> Dictionary:
	var wired: Array = []
	for action in _action_ids():
		if has(StringName(action)):
			wired.append(action)
	return {
		"actions": _action_ids(),
		"wired": wired,
		"ready": wired.size() == _action_ids().size(),
	}


func _callable_for(action: StringName) -> Callable:
	var callable: Callable = _actions().get(String(action), Callable())
	return callable


func _action_ids() -> Array:
	return [
		"list_templates",
		"read_active",
		"enter",
		"leave",
		"visit",
		"minimap",
		"rooms",
		"arm_fixture",
		"attempt_fixture",
		"claim_fixture",
	]


func _actions() -> Dictionary:
	return {
		"list_templates": list_templates,
		"read_active": read_active,
		"enter": enter,
		"leave": leave,
		"visit": visit,
		"minimap": minimap,
		"rooms": rooms,
		"arm_fixture": arm_fixture,
		"attempt_fixture": attempt_fixture,
		"claim_fixture": claim_fixture,
	}
