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
## fails the build if one appears. The retreat lengths below come from `TimeLadder`
## instead, which is the ONE calendar (`core/` is a layer `ui/` may depend on), so the
## cost line a player reads and the answer a retreat pays are two reads of one table.

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


## Whether the SEASON-SCALE verb is wired. Same decision as [method can_advance] and for
## the same reason: an unwired action must read as unavailable rather than as a button
## that renders and does nothing.
func can_retreat() -> bool:
	return _bridge != null and _bridge.has(&"retreat")


## Ask to sit for `periods` — the player's chosen duration, which ADR 0167 makes the
## cost rather than a menu entry. Returns the clock's own report, which answers
## `declared`, `paid`, `unpaid` and the crossed `magnitudes`.
func request_retreat(periods: int) -> Dictionary:
	if not can_retreat():
		return {"ok": false, "reason": "no_retreat"}
	return _bridge.call_action(&"retreat", [periods])


## ## The retreat lengths a player may choose, as primitives
##
## **Read from `TimeLadder.magnitudes()`, never from a list written here.** The ladder is
## the one calendar (`core/` is a layer `ui/` may depend on, so this is legal), and a
## second list of spans would be a second calendar that stays numerically identical until
## the day someone retunes the authored `.tres`. Each row is a whole period count the
## ladder itself authors, so every one of them is a span `TimeLadder.chunks_for` covers.
##
## **The base row is left out on purpose**: `period` is one period, which is what
## [method request_advance] already pays and what the wait button says out loud. A
## selector offering it would give a player two words for one verb.
func retreat_spans() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in TimeLadder.magnitudes():
		var magnitude := StringName(str(row.get("name", "")))
		var ratio := int(row.get("ratio_periods", 0))
		if magnitude == StringName() or magnitude == TimeLadder.BASE or ratio < 1:
			continue
		out.append({"magnitude": String(magnitude), "periods": ratio, "crossed": _crossed(ratio)})
	return out


## What `span_periods` crosses, as `{magnitude: whole count}`. The SSOT's own division,
## so a preview and the paid report are two reads of one calendar rather than a forecast
## computed beside the answer. The single fold is read back once per key — the loop walks
## the dictionary that fold returned, which is the shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts.
func _crossed(span_periods: int) -> Dictionary:
	var out: Dictionary = {}
	var crossed := TimeLadder.magnitudes_crossed(span_periods)
	for entry in crossed:
		if int(crossed[entry]) > 0:
			out[String(str(entry))] = int(crossed[entry])
	return out


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
		"can_retreat": can_retreat(),
		"retreat_spans": retreat_spans(),
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
