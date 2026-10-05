class_name WorldPulseBridge
extends RefCounted

## The injected view of the composition root's world clock, for the UI program.
##
## ## Why this exists at all
##
## The world's period tick is reachable from `app/` and from nowhere else. Measured
## before this file: `rg 'advance_one_period|world_summary' game/src/ui` returned
## nothing, so `WorldPulse.pull` ran on every frame of the running build and no
## surface read it — the tick existed, and no player could observe it or ask for it.
##
## `ui/` cannot fix that by reaching further. `app` is a [code]PRIVATE_UNITS[/code]
## entry (`tools/arch/rules.py`), so no screen may reference it at all, and the `event`
## module — the one that owns `EventApi.advance` — is **not** in
## [code]rules.UI_MODULES[/code], so a screen may not name `EventApi` either. Calling
## `EventApi.advance` from a screen would additionally be a SECOND dispatcher for one
## moment, which is ADR 0114's failure under a different name: the pulse offers
## ambient news, opens at most one event, settles the institutions and offers one
## period beat per period, and a screen calling the module would do none of that.
##
## So the tick arrives as plain callables, exactly as the `loot` module's screen
## receives [LootBridge]. The composition root fills this; a screen never names
## `WorldPulse`, `EventApi` or `WorldAmbient`.
##
## ## Three slots, and the third is the season-scale one
##
## [method read_state] and [method advance] were the whole seam. An earlier draft also
## carried a slot for `WorldPulse.available_events`, and it was cut: the event COUNT is
## already inside [method read_state]'s payload, and every extra slot is another line
## the composition root has to be edited for. A seam nobody lands is a feature that
## measures as dead — which is exactly how ADR 0167's season-scale class stayed dead
## until a `retreat` slot gave it somewhere to land.
##
## **The `retreat` slot is the difference between a wait and a chosen duration.** ADR
## 0167 decides that the player CHOOSES how long to sit and that the chosen length IS
## the cost, so this seam is the one action in the program whose argument is the price.
## It is a `Callable`, not a new panel and not a new route, because `ui/` may reach
## `app/` only through this file (`app` is a [code]PRIVATE_UNIT[/code]).
##
## Every callable returns primitives only, and an unwired callable reads as "not
## available" rather than as a failure — which is how a screen disables an action
## instead of pretending it worked.

## `ItemWorkbenchApp.world_summary()` -> Dictionary. The pulse's own primitives: the
## period count, the cadence, the beats, the world's event tally, and the roster of
## ambient facts under `ambient_facts`.
var read_state: Callable
## `ItemWorkbenchApp.advance_one_period()` -> Dictionary. The one verb that moves the
## world on demand, with no elapsed time at all. Takes no argument on purpose: a
## button and a headless driver can both say "one period" without knowing the cadence.
var advance: Callable
## `ItemWorkbenchPlay.retreat(periods: int)` -> Dictionary. The SEASON-SCALE verb
## (ADR 0167): `periods` is what the player chose to sit for and is paid through
## `advance_world`, so the report answers `declared`, `paid`, `unpaid` and the
## `magnitudes` the span crossed. One argument, an int — a duration is a COUNT of the
## clock's own unit here, never seconds, because nothing in `ui/` may hold a cadence
## (`tests/core/test_time_ladder_single_source.gd`'s UI clause).
var retreat: Callable


## Whether an action is wired. A screen reads this before it offers the action.
func has(action: StringName) -> bool:
	return _callable_for(action).is_valid()


func _callable_for(action: StringName) -> Callable:
	var callable: Callable = _actions().get(String(action), Callable())
	return callable


func _actions() -> Dictionary:
	return {"state": read_state, "advance": advance, "retreat": retreat}


## Invoke `action` with `args`, returning an empty dictionary when the callable is
## not wired or does not answer a dictionary. A screen never null-checks the bridge.
func call_action(action: StringName, args: Array = []) -> Dictionary:
	var callable := _callable_for(action)
	if not callable.is_valid():
		return {}
	var result = callable.callv(args)
	return result as Dictionary if result is Dictionary else {}
