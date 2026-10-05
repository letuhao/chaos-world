class_name WorldPulseReader
extends RefCounted

## Resolves the world's clock into the raw primitives `WorldPulsePanel` renders.
##
## ## Why this is not code in the screen
##
## `WorldMapScreen` draws a spatial graph of world locations, which is the other half
## of its 400-line budget. Reading a clock through a bridge is a different reason to
## change — a new figure the pulse publishes touches this file and not that one — so it
## lives here, next to the bridge it calls, and the screen keeps only the glue: bind,
## forward, nest the panel's summary. That is the same split `item_action_rules.gd` and
## `stat_presenter.gd` already make inside `ui/`.
##
## ## What it reads, and what it refuses to read
##
## The period count, the cadence and the ambient roster are the composition root's,
## reached through [WorldPulseBridge]'s plain callables. The `recorded` flag on each news
## row is NOT: it is read per fact out of the actor's ledger with `WorldFact`, because
## `core/` is a layer `ui/` may depend on and because the pulse publishes only a COUNT
## of how much of its roster the world has heard — a count cannot say WHICH.
##
## **No `WorldPulse` id or `PERIOD_SECONDS` literal appears here or anywhere else in
## `src/ui/`.** Both are `app/`'s, a second copy would stay numerically identical and go
## silently wrong the day the cadence is retuned, and `tests/ui/test_world_pulse.gd`
## fails the build if one appears.

## The root's callables. Null until the composition root fills it.
var _bridge: WorldPulseBridge = null


## Adopt the root's clock. Safe to call again, and safe before the actor is bound:
## `view` takes the actor per call rather than holding one, because the app mounts a
## screen before it hands that screen an actor.
func bind(bridge: WorldPulseBridge) -> void:
	_bridge = bridge


## Whether a player may ask for another period. The button's enabled state, and the
## only thing that decides it — a bridge nobody filled cannot be pressed.
func can_advance() -> bool:
	return _bridge != null and _bridge.has(&"advance")


## Ask for exactly one more period. Returns the report the clock answered, or a refusal
## naming why nothing happened, so the caller never has to null-check the bridge.
func request_advance() -> Dictionary:
	if not can_advance():
		return {"ok": false, "reason": "no_world_clock"}
	return _bridge.call_action(&"advance", [])


## The whole world view as primitives. Every key is a primitive and nothing here is
## formatted — the panel owns every `%d`, every duration and every sentence.
##
## An unwired bridge, and a wired one answering `{}`, are the same thing here: an absent
## clock. The panel is told so and says it out loud rather than rendering zeros.
func view(actor: Actor) -> Dictionary:
	var state := _state()
	return {
		"wired": not state.is_empty(),
		"can_advance": can_advance(),
		"periods": int(state.get("periods", 0)),
		"period_count": int(state.get("period_count", 0)),
		"period_seconds": float(state.get("period_seconds", 0.0)),
		"offered": int(state.get("offered", 0)),
		"claimed": int(state.get("claimed", 0)),
		"opened": int(state.get("opened", 0)),
		"active_events": int(state.get("active_events", 0)),
		"available_events": int(state.get("available_events", 0)),
		"news": news_rows(actor, state),
	}


## The world's own doings, as one `{fact, recorded}` row each.
##
## Wired, the roster is the pulse's `ambient_facts`: the authored catalogue, which is
## what lets a readout say "2 of 4 heard" and name the two still to come. Unwired, the
## only honest list is the ledger's own, so every row is something already heard.
##
## Each `for` walks an array built before it that neither branch appends to, which is
## the shape `test_no_unbounded_wait.gd` accepts.
func news_rows(actor: Actor, state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roster: Array = state.get("ambient_facts", []) as Array
	if roster.is_empty():
		for id in WorldFact.ids(actor):
			out.append({"fact": String(id), "recorded": true})
		return out
	for entry in roster:
		var fact := String(entry)
		if fact.is_empty():
			continue
		out.append({"fact": fact, "recorded": WorldFact.count(actor, StringName(fact)) > 0})
	return out


## The pulse's own report, or `{}`. Never through a `WorldPulse` reference: `app/` is a
## private unit and `ui/` may not name it.
func _state() -> Dictionary:
	if _bridge == null or not _bridge.has(&"state"):
		return {}
	return _bridge.call_action(&"state", [])
