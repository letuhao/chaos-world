class_name LootBridge
extends RefCounted

## The injected view of the `loot` module for the UI program.
##
## `ui/` is a pure consumer: it may reach a gameplay module only through that
## module's facade, and only for the modules the arch rules declare. `loot` is not
## declared there, so the composition root hands the screen plain callables
## instead of a module type. The screen therefore never names `LootApi` (or any
## item type), and the loot module never learns the UI exists — the two programs
## meet at this one object.
##
## Every callable returns primitives only: dictionaries of strings, numbers and
## booleans, or an empty dictionary when there is nothing to report. An invalid
## callable reads as "not available", which is how a screen disables an action
## rather than pretending it worked.

## `LootApi.domains()` -> Array
var list_domains: Callable
## `LootApi.enter_domain(actor, domain_id, tier_index, seed_value)` -> Dictionary
var enter_domain: Callable
## `LootApi.abandon(actor)` -> Dictionary
var leave_domain: Callable
## `LootApi.pickup(actor, encounter_id, drop_id)` -> Dictionary
var pickup: Callable
## `LootApi.pickup_all(actor, encounter_id)` -> Dictionary
var pickup_all: Callable
## `LootApi.reclaim(actor, stash_id)` -> Dictionary
var reclaim: Callable
## `LootApi.summary(actor)` -> Dictionary
var read_state: Callable

## There is deliberately no `strike` slot and no strike-damage number here (ADR 0076).
## This bridge used to carry a `damage` argument the caller chose, so a fight was however
## many presses that constant bought whatever the actor was made of, and nothing ever
## answered back — no fight could be lost. The exchange is now `CombatApi.exchange`, which
## `ui/` may call by name because `combat` is declared in `rules.UI_MODULES`, and it
## resolves both blows from the actor's own stats. A flat-damage slot here would not be
## redundant: it would be a live path that silently bypasses the whole model.


## Whether a callable is wired. A screen reads this before it offers an action.
func has(action: StringName) -> bool:
	return _callable_for(action).is_valid()


func _callable_for(action: StringName) -> Callable:
	var callable: Callable = _actions().get(String(action), Callable())
	return callable


func _actions() -> Dictionary:
	return {
		"domains": list_domains,
		"enter": enter_domain,
		"leave": leave_domain,
		"pickup": pickup,
		"pickup_all": pickup_all,
		"reclaim": reclaim,
		"state": read_state,
	}


## Invoke `action` with `args`, returning an empty dictionary when the callable is
## not wired or fails. A screen never has to null-check the bridge.
func call_action(action: StringName, args: Array = []) -> Dictionary:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return {}
	var result = callable.callv(args)
	return result as Dictionary if result is Dictionary else {}
