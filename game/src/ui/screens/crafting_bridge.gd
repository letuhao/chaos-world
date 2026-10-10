class_name CraftingBridge
extends RefCounted

## The injected view of the composition root's CRAFT action, for the crafting screen
## (ADR 0167, BL-0815).
##
## ## Why a bridge and not a direct call
##
## `ItemsApi.craft` is reachable from `ui/` (items is a `UI_MODULE`), but the WORLD PERIOD
## a craft costs is not: the clock is `app/`'s, and `app` is a `PRIVATE_UNIT` no screen may
## name. So the craft arrives as a plain callable the composition root fills, exactly as
## `WorldPulseBridge` carries the wait and the retreat — the same shape `LootBridge` and
## `DomainBridge` already use. A screen that crafted through `ItemsApi` directly would
## still be FREE, which is the gap ADR 0167 exists to close.
##
## ## A craft is PERIOD-SCALE
##
## ADR 0167's table puts craft in the 1..8-period class: a short deliberate act, not a
## season. The composition root owns the number and the clock; this seam carries only the
## ask and the report.
##
## Every callable returns primitives only, and an unwired callable reads as "not
## available" rather than as a failure — which is how a screen falls back instead of
## pretending the clock was paid.

## `ItemWorkbenchPlay.craft_with_time(recipe: Resource)` -> Dictionary. `recipe` is the
## authored resource the screen already holds; the answer is `{ok, reason, made, paid,
## periods}`. An unwired slot answers `{}`, so a screen can tell "no clock was injected"
## from "the craft was refused".
var craft: Callable


## Whether an action is wired. A screen reads this before it offers the action.
func has(action: StringName) -> bool:
	return _callable_for(action).is_valid()


## Invoke `action` with `args`, returning an empty dictionary when the callable is not
## wired or does not answer a dictionary. A screen never null-checks the bridge.
func call_action(action: StringName, args: Array = []) -> Dictionary:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return {}
	var result = callable.callv(args)
	return result as Dictionary if result is Dictionary else {}


func _callable_for(action: StringName) -> Callable:
	return _actions().get(String(action), Callable())


func _actions() -> Dictionary:
	return {"craft": craft}
