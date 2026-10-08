class_name InteractionLog
extends RefCounted

## A bounded interaction history for one partner (ADR 0892).
##
## **This is a log, not a ledger.** The oldest entry is evicted when full — eviction is
## safe because the aggregate `total_interactions` and `frequent_partner_tier` are stored
## separately on the RelationshipEntry and never evicted.
##
## Entries older than 30 days are pruned during `tick()`. Pruning is bounded — it
## iterates the fixed 100-entry array once.

const CAPACITY := 100
const PRUNE_DAYS := 30.0

var _entries: Array[Dictionary] = []


func _init(entries: Array[Dictionary] = []) -> void:
	for entry in entries:
		if entry is Dictionary:
			_entries.append(entry.duplicate())


## Log an interaction. Evicts the oldest entry if at capacity.
func add(
	type: StringName,
	emotional_delta: Dictionary = {},
	timestamp: float = 0.0,
	dc_session: bool = false
) -> void:
	var entry := {
		"type": String(type),
		"emotional_delta": emotional_delta,
		"timestamp": timestamp,
		"dc_session": dc_session,
	}
	_entries.append(entry)
	if _entries.size() > CAPACITY:
		_entries.pop_front()


## Prune entries older than `PRUNE_DAYS` days before `now`.
func prune(now: float) -> int:
	var cutoff := now - (PRUNE_DAYS * 86400.0)
	var pruned := 0
	var kept: Array[Dictionary] = []
	for entry in _entries:
		var ts := float(entry.get("timestamp", 0.0))
		if ts >= cutoff:
			kept.append(entry)
		else:
			pruned += 1
	_entries = kept
	return pruned


## All entries since `timestamp`.
func entries_since(timestamp: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if float(entry.get("timestamp", 0.0)) >= timestamp:
			out.append(entry)
	return out


## All entries of a given type.
func entries_by_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if StringName(entry.get("type", &"")) == type:
			out.append(entry)
	return out


## Count of entries of a given type.
func count_by_type(type: StringName) -> int:
	var count := 0
	for entry in _entries:
		if StringName(entry.get("type", &"")) == type:
			count += 1
	return count


## Count of dual cultivation sessions.
func dc_session_count() -> int:
	var count := 0
	for entry in _entries:
		if bool(entry.get("dc_session", false)):
			count += 1
	return count


func size() -> int:
	return _entries.size()


func to_dict() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		out.append(entry.duplicate())
	return out


static func from_dict(entries: Array[Dictionary]) -> InteractionLog:
	return InteractionLog.new(entries)
