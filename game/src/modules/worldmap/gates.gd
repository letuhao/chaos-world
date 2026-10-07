class_name WorldmapGates
extends RefCounted

## Hook-gated travel: who may cross an edge, decided outside the map system.
##
## An edge names an optional `hook` (a plain String id). No hook means no gate
## and the edge passes — openness is the default, because most doorways are
## just doorways. A hook WITH an installed evaluator calls it as
## `evaluator.call(edge, context)`; a hook with NOTHING installed refuses
## `unknown_gate` rather than passing, because a gate nobody wired is a lock
## nobody holds, and an open lock that reads as a wall is honest while a
## missing lock that reads as open is a hole.
##
## The evaluators live here (one static table, reset by `clear`) and are
## installed by `app/` — the same seam shape as the domain world's observer:
## the module owns the question, the composition root owns the answer. Tests
## reset through `clear`.
##
## A verdict is a bool or a `{ok, reason}` Dictionary. Anything else refuses
## `bad_verdict`: an evaluator that cannot answer is not an approval.

static var _evaluators: Dictionary = {}


## Install the evaluator for `hook_id`. Refuses an empty id and a dead
## Callable by name; re-installing replaces, so a boot re-mount never stacks.
static func register(hook_id: String, evaluator: Callable) -> Dictionary:
	if hook_id.is_empty():
		return {"ok": false, "reason": "empty_hook"}
	if not evaluator.is_valid():
		return {"ok": false, "reason": "dead_evaluator", "hook": hook_id}
	_evaluators[hook_id] = evaluator
	return {"ok": true, "reason": "", "hook": hook_id}


## Forget every evaluator. Tests only: production installs once at boot.
static func clear() -> void:
	_evaluators.clear()


## Whether `hook_id` has an evaluator installed.
static func has(hook_id: String) -> bool:
	return _evaluators.has(hook_id)


## Answer the edge. `context` is the caller's to fill (actor facts, flags,
## tolls paid) — the map system never invents it, so it can never disagree
## with the game about what is true.
static func evaluate(edge: Dictionary, context: Dictionary) -> Dictionary:
	var hook_id := String(edge.get("hook", ""))
	if hook_id.is_empty():
		return {"ok": true, "reason": ""}
	if not _evaluators.has(hook_id):
		return {"ok": false, "reason": "unknown_gate", "hook": hook_id}
	var verdict: Variant = (_evaluators[hook_id] as Callable).call(
		(edge as Dictionary).duplicate(true), (context as Dictionary).duplicate(true)
	)
	if verdict is bool:
		return {"ok": bool(verdict), "reason": "" if bool(verdict) else "refused"}
	if verdict is Dictionary:
		return {
			"ok": bool((verdict as Dictionary).get("ok", false)),
			"reason": String((verdict as Dictionary).get("reason", "")),
		}
	return {"ok": false, "reason": "bad_verdict", "hook": hook_id}
