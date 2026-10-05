class_name QuestState
extends RefCounted

## The versioned quest ledger, stored as a plain dictionary under
## `actor.module_data["quest_state"]` (ADR 0027 pattern, `DestinyState` precedent).
## Core persists it without ever naming a quest type.
##
## `{version, active: {quest_id: {started, completed, failed}}, offered: [quest_id]}`
##
## **It records WHEN and WHETHER, never HOW MUCH.** A step's progress is a count
## in the shared world ledger (ADR 0113), not a number kept here. That is the
## entire architectural claim: there is exactly one copy of "the player did X"
## in a save, and it is not this file's. A per-quest counter column would be the
## fourth copy ADR 0113 exists to delete.
##
## Monotone in the same direction as the ledger it reads: a quest is started,
## completed or failed, and none of those is undone by a normalize pass. The one
## exception is explicit and deliberate — an entry naming content the catalog no
## longer ships is dropped, because persisting a quest nothing can display would
## be a save smuggling in content this build does not have.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"quest_state"


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## A known-quest filter. `known_quests` comes from the catalog; an entry naming
## content that no longer ships is dropped rather than persisted, mirroring
## `DestinyState.normalize`.
static func normalize(payload: Dictionary, known_quests: Dictionary = {}) -> Dictionary:
	var out := {"version": SCHEMA_VERSION, "active": {}, "offered": []}
	if payload.is_empty():
		return out
	var active = payload.get("active", {})
	if active is Dictionary:
		for quest_id in (active as Dictionary).keys():
			var entry = (active as Dictionary)[quest_id]
			if not (entry is Dictionary):
				continue
			if not known_quests.is_empty() and not known_quests.has(String(quest_id)):
				continue
			# Rebuilt field by field rather than copied, for `DestinyState`'s
			# reason: a file-backed save makes one JSON hop, JSON has a single
			# number type, and a copied int comes back as 2.0 and stops comparing
			# equal to itself across a round trip.
			out["active"][String(quest_id)] = {
				# An empty `started` reads as 0, which is falsy but valid: a
				# quest accepted before any clock existed has no start time, and
				# inventing one would be a lie about when the player took it.
				"started": int((entry as Dictionary).get("started", 0)),
				# `completed` and `failed` are WHETHER, not WHEN — booleans, not
				# moments. They were stored as integers and read with `> 0`, which
				# only works if somebody writes a non-zero moment; the sole caller
				# passed 0 (the module owns no clock, DEF-0111), so `completed` was
				# always 0, `is_completed` was always false, and completion was
				# never once — `advance()` re-paid a quest on every call. Coerced
				# here so a save holding 1/0 still reads correctly.
				"completed": _flag((entry as Dictionary).get("completed", false)),
				"failed": _flag((entry as Dictionary).get("failed", false)),
			}
	var offered = payload.get("offered", [])
	if offered is Array:
		for quest_id in offered as Array:
			var key := String(quest_id)
			if known_quests.is_empty() or known_quests.has(key):
				out["offered"].append(key)
	return out


## The entry for `quest_id`, or an EMPTY one when the quest is not tracked.
##
## An empty dictionary rather than null, because a typed `-> Dictionary` that
## returns null is a runtime error in GDScript and it is a fatal one: it aborted
## [method entry] before its caller could test for the absence, so every
## `is_completed` on an untracked quest raised instead of answering false.
## "Not tracked" is therefore spelled [code]{}[/code], which is also falsy in
## every read, so an untracked quest and an entry with no flags agree.
static func entry(ledger: Dictionary, quest_id: StringName) -> Dictionary:
	var found = (ledger.get("active", {}) as Dictionary).get(String(quest_id), null)
	if found is Dictionary:
		return found as Dictionary
	return {}


## Whether `quest_id` has an entry at all, active or finished.
static func is_tracked(ledger: Dictionary, quest_id: StringName) -> bool:
	return (ledger.get("active", {}) as Dictionary).has(String(quest_id))


## Whether `quest_id` has been completed. The once-guard reads this and nothing
## else, so "already completed" is answerable without re-walking the ledger.
static func is_completed(ledger: Dictionary, quest_id: StringName) -> bool:
	return _flag(entry(ledger, quest_id).get("completed", false))


## Whether `quest_id` has been failed.
static func is_failed(ledger: Dictionary, quest_id: StringName) -> bool:
	return _flag(entry(ledger, quest_id).get("failed", false))


## Every tracked-but-unfinished quest id, canonically ordered. `active()` in the
## facade reads this, so "active" means "in flight", never "seen at some point".
static func active_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for quest_id in (ledger.get("active", {}) as Dictionary).keys():
		var found := (ledger.get("active", {}) as Dictionary)[quest_id] as Dictionary
		if _flag(found.get("completed", false)) or _flag(found.get("failed", false)):
			continue
		strings.append(String(quest_id))
	strings.sort()
	var out: Array[StringName] = []
	for quest_id in strings:
		out.append(StringName(quest_id))
	return out


## Every completed quest id, canonically ordered.
static func completed_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for quest_id in (ledger.get("active", {}) as Dictionary).keys():
		var found := (ledger.get("active", {}) as Dictionary)[quest_id] as Dictionary
		if not _flag(found.get("completed", false)):
			continue
		strings.append(String(quest_id))
	strings.sort()
	var out: Array[StringName] = []
	for quest_id in strings:
		out.append(StringName(quest_id))
	return out


## Mark `quest_id` started, if it is not tracked yet. Returns true when this call
## is what created the entry, so a caller can tell "accepted" from "already
## accepted" without comparing a dictionary.
static func begin(ledger: Dictionary, quest_id: StringName, at: int) -> bool:
	var active: Dictionary = ledger["active"]
	var key := String(quest_id)
	if active.has(key):
		return false
	active[key] = {"started": at, "completed": false, "failed": false}
	return true


## Mark `quest_id` completed. **This is the once-guard.** It returns false and
## writes nothing when the quest is already completed, so no caller can pay a
## grant twice no matter how it reached here (ADR 0061's precedent: the reward
## is decided once, and the decision lives in one place).
##
## No `at`: this records WHETHER, and the module owns no clock to say WHEN
## (DEF-0111). It used to take a moment and was called with `0`, so it wrote
## `completed = 0` into a field every reader tested with `> 0` — the guard was
## inert and a quest completed and paid on every single `advance()`.
static func finish(ledger: Dictionary, quest_id: StringName) -> bool:
	var active: Dictionary = ledger["active"]
	var key := String(quest_id)
	if not active.has(key):
		# Completing something never started is refused rather than invented: an
		# entry fabricated here would carry a `started` the player never had.
		return false
	var entry: Dictionary = active[key]
	if _flag(entry.get("completed", false)):
		return false
	entry["completed"] = true
	return true


## Mark `quest_id` failed. Once-guard on the same axis as `finish`, and no `at`
## for the same reason.
static func fail(ledger: Dictionary, quest_id: StringName) -> bool:
	var active: Dictionary = ledger["active"]
	var key := String(quest_id)
	if not active.has(key):
		return false
	var entry: Dictionary = active[key]
	if _flag(entry.get("failed", false)) or _flag(entry.get("completed", false)):
		return false
	entry["failed"] = true
	return true


## One WHETHER flag, coerced. Any truthy stored value means yes, so a save
## written by the integer era (`1`) and one written by this one (`true`) are the
## same state — a save is untrusted input and must not be able to state a
## completion this build cannot see.
static func _flag(value) -> bool:
	if value is bool:
		return value as bool
	if value is int or value is float:
		return int(value) != 0
	return false
