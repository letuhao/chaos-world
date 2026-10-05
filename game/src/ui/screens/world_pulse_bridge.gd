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
## ## Four slots, and the fourth is the one a count could not carry
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
## **`events` is the fourth, and it is what the cut was protecting against the WRONG
## defect** (see the note on [member events]).
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
## `WorldPulse.open_events()` -> Array[Dictionary]. **The first READ slot on this seam,
## and the one that turns a count into a thing** (BL-0906). One primitive row per event
## the world has open right now, copied out of the event module's read model by `app/`:
## `event_id`, `display_name`, `stage_name`, `stage_index`, `stage_count`, `periods_held`,
## `duration_periods`, `standoff_id`, `is_final_stage` and the rest of the shape
## `EventReadModel.open_rows` publishes. `ui/` may not name that module, so this row is
## the only description of an open event a screen can legally hold.
##
## **The cut `available_events` slot above was right about the verb and wrong about the
## seam.** The COUNT was already inside [method read_state]'s payload — and a count cannot
## say WHICH event is open, what stage it has reached, how long it has held, or what its
## standoff pays. A slot is about the SHAPE of the answer, not its size: a payload key may
## be added or renamed without editing the composition root, whereas a slot is a second,
## NAMED edge whose absence is visible from `has()` — and that visibility is the only thing
## that lets a screen name a missing seam instead of rendering a silent zero. Naming it is
## what makes the gap measurable; a key nobody reads is the defect the cut was avoiding.
##
## **Returns an ARRAY, not a `Dictionary`, and `call_action` is deliberately not its
## reader.** `call_action` answers a dictionary by contract, so wrapping these rows in a
## `{"rows": [...]}` would be a shape that exists only because the bridge returns
## dictionaries everywhere else. An unwired slot answers `[]` — which a panel cannot tell
## from a world with nothing open — so `has_events()` exists beside it, and that
## distinction is the empty-state question this slot exists to answer honestly.
var events: Callable


## Whether an action is wired. A screen reads this before it offers the action.
func has(action: StringName) -> bool:
	return _callable_for(action).is_valid()


## Whether the EVENT ROWS are wired. Split from [method has] because an empty answer and an
## unwired slot are the same `[]`, and they are different things to a player: a world with
## nothing open, and a screen nobody published an event row to. A panel that could not tell
## them apart would render the second as the first — which is exactly the empty list that
## reads as a bug this slot exists to remove.
func has_events() -> bool:
	return events.is_valid()


## Every open event row this bridge was given, or `[]` when the slot is unwired or nothing
## is open. **Rows are copied on the way out**, so a screen that edits what it was handed
## cannot write back into a payload the composition root may still be holding.
func open_event_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not events.is_valid():
		return out
	var rows = events.call()
	if not rows is Array:
		return out
	for row in rows as Array:
		if row is Dictionary:
			out.append((row as Dictionary).duplicate(true))
	return out


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
