class_name RelationshipState
extends RefCounted

## An actor's whole relationship log (ADR 0123).
##
## **One log per actor.** Every partner the player has interacted with gets one entry.
## The log is stored in `actor.module_data[MODULE_KEY]`, never in a bespoke save slot.
##
## `changed` is emitted on every mutation so a `StatProvider` reading this log is
## invalidated the same way `SocialState` is.

signal changed

const MODULE_KEY := &"relationship_state"
const SCHEMA_VERSION := 1

var _entries: Dictionary = {}


func _init() -> void:
	pass


## The entry for `partner_id`, or null when they have never interacted.
func entry(partner_id: StringName) -> RelationshipEntry:
	return _entries.get(String(partner_id))


## Get or create the entry for `partner_id`.
func ensure_entry(partner_id: StringName, type: StringName = RelationshipType.NONE) -> RelationshipEntry:
	var key := String(partner_id)
	if not _entries.has(key):
		_entries[key] = RelationshipEntry.new(partner_id, type)
	return _entries[key]


func partner_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _entries.keys():
		out.append(StringName(key))
	out.sort()
	return out


func entry_count() -> int:
	return _entries.size()


## All active (not ended) entries.
func active_entries() -> Array[RelationshipEntry]:
	var out: Array[RelationshipEntry] = []
	for key in _entries.keys():
		var entry := _entries[key] as RelationshipEntry
		if entry != null and entry.is_active():
			out.append(entry)
	return out


## Count of active romantic/spouse relationships.
func active_romantic_count() -> int:
	var count := 0
	for key in _entries.keys():
		var entry := _entries[key] as RelationshipEntry
		if entry != null and entry.is_active() and (entry.relationship_type == RelationshipType.ROMANTIC or entry.relationship_type == RelationshipType.SPOUSE):
			count += 1
	return count


## Count of active DC partners.
func active_dc_partner_count() -> int:
	var count := 0
	for key in _entries.keys():
		var entry := _entries[key] as RelationshipEntry
		if entry != null and entry.is_active() and entry.is_dual_cultivation_partner:
			count += 1
	return count


## The highest frequent partner tier across all entries.
func highest_tier() -> int:
	var best := 0
	for key in _entries.keys():
		var entry := _entries[key] as RelationshipEntry
		if entry != null and entry.frequent_partner_tier > best:
			best = entry.frequent_partner_tier
	return best


## Total emotional energy across all active entries.
func emotional_energy() -> float:
	var total := 0.0
	for key in _entries.keys():
		var entry := _entries[key] as RelationshipEntry
		if entry != null and entry.is_active():
			total += entry.emotional_signature.joy * 10.0
			total += entry.emotional_signature.trust * 5.0
	return clampf(total, 0.0, 100.0)


func mark_changed() -> void:
	changed.emit()


func to_dict() -> Dictionary:
	var entries := {}
	for key in _entries.keys():
		entries[key] = _entries[key].to_dict()
	return {
		"version": SCHEMA_VERSION,
		"entries": entries,
	}


static func from_dict(payload: Dictionary) -> RelationshipState:
	var state := RelationshipState.new()
	if payload.is_empty():
		return state
	var entries = payload.get("entries", {})
	if entries is Dictionary:
		for key in (entries as Dictionary).keys():
			var entry_data = (entries as Dictionary)[key]
			if entry_data is Dictionary:
				state._entries[key] = RelationshipEntry.from_dict(entry_data)
	return state
