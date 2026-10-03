class_name AnchorState
extends RefCounted

## The versioned anchor ledger, stored in an INJECTED store (ADR 0132).
##
## ## Why a store and not `actor.module_data`
##
## An anchor is a WORLD fact: it is raised in a place, it outlives the body that raised it, and
## a rival must be able to see it standing. ADR 0101 settled this shape for a world object and
## named the failure exactly — a per-actor copy lets a rival read a raised structure as absent
## and raise their own on the same ground. A soul outlives its body (ADR 0127), so the thing an
## anchor repairs is already store-backed, and the anchor belongs beside it.
##
## The actor mirror is kept only because a save carries it, exactly as ADR 0101 specifies.

const SCHEMA_VERSION := 1
## The store's ledger key, and the actor mirror's `module_data` key.
const MODULE_KEY := &"anchor_state"

## Bounded, so a save cannot grow without limit — the `DestinyState.HISTORY_LIMIT` reason.
const HISTORY_LIMIT := 32


## Normalize a payload into the one shape this module reads.
##
## `known_anchors` is the catalog's answer and an entry naming content it no longer ships is
## DROPPED rather than persisted, so a save from a wider content build cannot smuggle in a
## structure this build cannot answer for.
static func normalize(payload: Dictionary, known_anchors: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"raised": {},
		"debt": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	var raised = payload.get("raised", {})
	if raised is Dictionary:
		for anchor_id in (raised as Dictionary).keys():
			if not known_anchors.is_empty() and not known_anchors.has(String(anchor_id)):
				continue
			out["raised"][String(anchor_id)] = {
				"integrity": maxi(0, _number((raised as Dictionary)[anchor_id], 0)),
				"at":
				(
					String((raised as Dictionary)[anchor_id].get("at", ""))
					if ((raised as Dictionary)[anchor_id] is Dictionary)
					else ""
				),
			}
	var debt = payload.get("debt", {})
	if debt is Dictionary:
		for anchor_id in (debt as Dictionary).keys():
			if not known_anchors.is_empty() and not known_anchors.has(String(anchor_id)):
				continue
			out["debt"][String(anchor_id)] = maxi(0, _number((debt as Dictionary)[anchor_id], 0))
	out["history"] = _trail(payload.get("history", []))
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## Whether `anchor_id` stands raised in this world.
static func is_raised(ledger: Dictionary, anchor_id: StringName) -> bool:
	return (ledger.get("raised", {}) as Dictionary).has(String(anchor_id))


## The integrity recorded against `anchor_id`, or 0.
static func raised_integrity(ledger: Dictionary, anchor_id: StringName) -> int:
	var entry = (ledger.get("raised", {}) as Dictionary).get(String(anchor_id))
	if not (entry is Dictionary):
		return 0
	return int((entry as Dictionary).get("integrity", 0))


## Charge `amount` against `anchor_id`'s build cost. Returns what is STILL owed, never a
## negative: a caller that overpays is told it overpaid rather than handed a credit nothing
## reads.
static func charge_debt(ledger: Dictionary, anchor_id: StringName, amount: int) -> int:
	var key := String(anchor_id)
	var owed := maxi(0, int((ledger.get("debt", {}) as Dictionary).get(key, 0)) - maxi(0, amount))
	if owed <= 0:
		(ledger["debt"] as Dictionary).erase(key)
		return 0
	(ledger["debt"] as Dictionary)[key] = owed
	return owed


## Record `anchor_id` as standing raised.
static func raise(ledger: Dictionary, anchor_id: StringName, at: String) -> void:
	var key := String(anchor_id)
	(ledger["debt"] as Dictionary).erase(key)
	(ledger["raised"] as Dictionary)[key] = {"integrity": 0, "at": at}


## Every raised anchor id, sorted. A codex listing them must not reorder between reads, and a
## `DirAccess` walk is not a stable order.
static func raised_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in (ledger.get("raised", {}) as Dictionary).keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


# --- Internals -------------------------------------------------------------


## `value` as an int, or `fallback` when it is not a number. `int()` on a String is a RUNTIME
## error in GDScript, so an unreadable save would abort `normalize` rather than being
## diagnosed — and an unreadable payload must normalize, never throw.
static func _number(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


## The bounded build/damage trail, rebuilt field by field: JSON has one number type, so a
## copied count comes back as a float and the ledger stops comparing equal to itself.
static func _trail(value) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		(
			out
			. append(
				{
					"kind": String(row.get("kind", "")),
					"anchor_id": String(row.get("anchor_id", "")),
					"amount": _number(row.get("amount", 0), 0),
				}
			)
		)
		if out.size() >= HISTORY_LIMIT:
			break
	return out
