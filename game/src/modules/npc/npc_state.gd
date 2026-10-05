class_name NpcState
extends RefCounted

## The roster ledger (ADR 0077). Stored in the PLAYER actor's `module_data`, exactly as
## `race_state` and `destiny_state` are — so `Actor.to_dict` round-trips it and there is
## **no second save file** (ADR 0027, and ADR 0074's "no bespoke save path").
##
## The registry below is an INDEX over this ledger, rebuilt on `attach`. It holds the live
## actors for npcs currently in a room and nothing else: it is not the truth and is never
## persisted, so it cannot drift from what a save says.

signal changed

const MODULE_KEY := &"npc_state"
const SCHEMA_VERSION := 1

## Bounded roster. A world with more tracked npcs than this fails loudly at the cap
## rather than writing a save that grows without limit.
const MAX_ROSTER := 256

var _entries: Dictionary = {}


func _init() -> void:
	pass


func entry(npc_id: StringName) -> NpcRosterEntry:
	return _entries.get(String(npc_id))


func has_entry(npc_id: StringName) -> bool:
	return _entries.has(String(npc_id))


## Add or return the entry for a tracked npc. Returns null — refusing, not trimming —
## once `MAX_ROSTER` is reached.
func ensure_entry(npc_id: StringName, def_id: StringName) -> NpcRosterEntry:
	var key := String(npc_id)
	if _entries.has(key):
		return _entries[key]
	if _entries.size() >= MAX_ROSTER:
		return null
	var created := NpcRosterEntry.new(npc_id, def_id)
	_entries[key] = created
	changed.emit()
	return created


## The ids this ledger holds, in a DETERMINISTIC order.
##
## ## The sort is by the id's TEXT, and it has to be
##
## `out.sort()` sorted an `Array[StringName]`, and Godot compares `StringName` by its
## internal pointer-derived id — not by the string it holds. So the order was a property of
## which ids happened to intern first in the process, and it CHANGED between runs: two
## suites loaded in one order got `[drifter, smith_bearcutter]` and the same two loaded in
## another got `[smith_bearcutter, drifter]`, and `test_npc_content.gd`'s three ordering
## assertions went red on a run where they had been green on the previous one.
##
## Every consumer of this list wants a roster a player can read — a save round trip, a diff,
## a "who have I met" screen — and a list whose order moves between two runs of the same
## world is not that. Sorting the TEXTS and re-interning is one named call, and it makes the
## order a property of the ids rather than of the session.
func npc_ids() -> Array[StringName]:
	var texts: Array[String] = []
	for key in _entries.keys():
		texts.append(String(key))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out


func entry_count() -> int:
	return _entries.size()


## Tracked ids only. What a "who have I met" screen lists.
func tracked_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for npc_id in npc_ids():
		var entry := entry(npc_id)
		if entry != null and entry.tracked():
			out.append(npc_id)
	return out


func remove(npc_id: StringName) -> bool:
	if not _entries.has(String(npc_id)):
		return false
	_entries.erase(String(npc_id))
	changed.emit()
	return true


func mark_changed() -> void:
	changed.emit()


func to_dict() -> Dictionary:
	var entries := {}
	for key in _entries.keys():
		entries[String(key)] = _entries[key].to_dict()
	return {"version": SCHEMA_VERSION, "entries": entries}


static func from_dict(data: Dictionary) -> NpcState:
	var state := NpcState.new()
	for key in data.get("entries", {}).keys():
		var entry := NpcRosterEntry.from_dict(data["entries"][key])
		if state._entries.size() >= MAX_ROSTER:
			# Refuse the overflow rather than silently keeping a partial world; a save
			# that dropped a story npc would fail later and far from the cause.
			break
		state._entries[String(key)] = entry
	return state


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "entries": {}}
