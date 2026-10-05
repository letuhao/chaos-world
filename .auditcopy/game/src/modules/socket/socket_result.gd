class_name SocketResult
extends RefCounted

## One transaction's answer, in the shape every socket action returns and the
## shape the change notification carries. A result is never partial: `ok` is
## true only when the whole transaction committed, and `reason` is the gameplay
## cause otherwise — never a UI string.

const OK := &"ok"


## A committed transaction. `cost` is what was consumed, `effect` what changed.
static func committed(
	action: StringName, target: StringName, cost: Array = [], effect: Dictionary = {}
) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"action": String(action),
		"target": String(target),
		"cost": cost.duplicate(),
		"effect": effect.duplicate(true),
	}


## A refused transaction. Nothing was consumed and nothing changed.
static func refused(action: StringName, target: StringName, reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"action": String(action),
		"target": String(target),
		"cost": [],
		"effect": {},
	}


## Whether a result committed.
static func committed_ok(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


## The gameplay reason on a refusal, or "" for a commit.
static func reason_of(result: Dictionary) -> String:
	return String(result.get("reason", ""))
