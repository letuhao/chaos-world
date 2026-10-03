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
				"completed": int((entry as Dictionary).get("completed", 0)),
				"failed": int((entry as Dictionary).get("failed", 0)),
			}
	var offered = payload.get("offered", [])
	if offered is Array:
		for quest_id in offered as Array:
			var key := String(quest_id)
			if known_quests.is_empty() or known_quests.has(key):
				out["offered"].append(key)
	return out


## The entry for `quest_id`, or null when the quest is not tracked.
static func entry(ledger: Dictionary, quest_id: StringName) -> Dictionary:
	return (ledger.get("active", {}) as Dictionary).get(String(quest_id), null)


## Whether `quest_id` has an entry at all, active or finished.
static func is_tracked(ledger: Dictionary, quest_id: StringName) -> bool:
	return (ledger.get("active", {}) as Dictionary).has(String(quest_id))


## Whether `quest_id` has been completed. The once-guard reads this and nothing
## else, so "already completed" is answerable without re-walking the ledger.
static func is_completed(ledger: Dictionary, quest_id: StringName) -> bool:
	var found := entry(ledger, quest_id)
	if found == null:
		return false
	return int(found.get("completed", 0)) > 0


## Whether `quest_id` has been failed.
static func is_failed(ledger: Dictionary, quest_id: StringName) -> bool:
	var found := entry(ledger, quest_id)
	if found == null:
		return false
	return int(found.get("failed", 0)) > 0


## Every tracked-but-unfinished quest id, canonically ordered. `active()` in the
## facade reads this, so "active" means "in flight", never "seen at some point".
static func active_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for quest_id in (ledger.get("active", {}) as Dictionary).keys():
		var found := (ledger.get("active", {}) as Dictionary)[quest_id] as Dictionary
		if int(found.get("completed", 0)) > 0 or int(found.get("failed", 0)) > 0:
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
		if int(found.get("completed", 0)) <= 0:
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
	active[key] = {"started": at, "completed": 0, "failed": 0}
	return true


## Mark `quest_id` completed. **This is the once-guard.** It returns false and
## writes nothing when the quest is already completed, so no caller can pay a
## grant twice no matter how it reached here (ADR 0061's precedent: the reward
## is decided once, and the decision lives in one place).
static func finish(ledger: Dictionary, quest_id: StringName, at: int) -> bool:
	var active: Dictionary = ledger["active"]
	var key := String(quest_id)
	if not active.has(key):
		# Completing something never started is refused rather than invented: an
		# entry fabricated here would carry a `started` the player never had.
		return false
	var entry: Dictionary = active[key]
	if int(entry.get("completed", 0)) > 0:
		return false
	entry["completed"] = at
	return true


## Mark `quest_id` failed. Once-guard on the same axis as `finish`.
static func fail(ledger: Dictionary, quest_id: StringName, at: int) -> bool:
	var active: Dictionary = ledger["active"]
	var key := String(quest_id)
	if not active.has(key):
		return false
	var entry: Dictionary = active[key]
	if int(entry.get("failed", 0)) > 0 or int(entry.get("completed", 0)) > 0:
		return false
	entry["failed"] = at
	return true
