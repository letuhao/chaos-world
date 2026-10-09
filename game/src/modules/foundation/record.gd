class_name FoundationRecord
extends RefCounted

## The shared foundation record (BL-0951 / ADR 0939): one PERFECTION snapshot per
## realm an actor has LEFT, plus the carried aggregate the paths gate on.
##
## ## The shared half, and only the shared half
##
## This module owns the record and the vocabulary; each cultivation path implements its
## own rules over them — its own `min_foundation` demand, its own tribulation scaling,
## its own principle-based measurement. Nothing here learns a path's formula, and no
## path keeps a second copy of the record (ADR 0066).
##
## **No combat stats.** Foundation gates and scales breakthroughs and nothing else, so
## the actor-vs-actor census stays flat.
##
## ## Snapshots are WRITE-ONCE
##
## A realm's perfection is written the moment the actor leaves it and can never be
## rewritten — that is the point of the program (a past choice is a debt the future
## collects). The underlying stats stay trainable (ADR 0939: snapshot, never a lock),
## so nothing goes dead.
##
## ## Persistence
##
## `module_data[FoundationRecord.SLOT]`, a plain versioned dictionary applied through
## `Actor.set_module_data` (ADR 0027's pattern) — never a serialized type, never a
## second copy on the actor.

const SLOT := &"foundation"
const SCHEMA_VERSION := 1


## The empty record. A fresh actor carries this rather than a missing key, so "no
## realms left yet" and "the module is not attached" are different states.
static func blank() -> Dictionary:
	return {"version": SCHEMA_VERSION, "snapshots": {}}


## A usable record from anything `module_data` may hold. A payload written before a
## field existed loads with that field empty rather than failing, the version is stamped
## on the way out, and every snapshot is clamped into [0, 1] — a hand-edited save buys
## nothing the program forbids.
static func normalize(raw: Dictionary) -> Dictionary:
	var record := blank()
	if raw.is_empty():
		return record
	var snapshots: Variant = raw.get("snapshots", {})
	if snapshots is Dictionary:
		for key in (snapshots as Dictionary).keys():
			var value: Variant = (snapshots as Dictionary)[key]
			if not (value is float or value is int):
				continue
			var perfection := float(value)
			if not is_finite(perfection):
				continue
			(record["snapshots"] as Dictionary)[StringName(key)] = clampf(perfection, 0.0, 1.0)
	record["version"] = SCHEMA_VERSION
	return record


static func has_snapshot(record: Dictionary, realm_id: StringName) -> bool:
	return (record.get("snapshots", {}) as Dictionary).has(realm_id)


static func snapshot_for(record: Dictionary, realm_id: StringName) -> float:
	return float((record.get("snapshots", {}) as Dictionary).get(realm_id, 0.0))


## How many realms the actor has left.
static func count(record: Dictionary) -> int:
	return (record.get("snapshots", {}) as Dictionary).size()


## The carried aggregate: the mean of every snapshot, `0.0` when none exists. The paths
## decide what to do with it; this is the one arithmetic the shared half owns.
static func aggregate(record: Dictionary) -> float:
	var snapshots: Dictionary = record.get("snapshots", {})
	if snapshots.is_empty():
		return 0.0
	var total := 0.0
	for value in snapshots.values():
		total += float(value)
	return total / float(snapshots.size())


## A copy of `record` with one snapshot added. Pure: the caller applies it.
static func with_snapshot(
	record: Dictionary, realm_id: StringName, perfection: float
) -> Dictionary:
	var out := normalize(record)
	(out["snapshots"] as Dictionary)[realm_id] = clampf(perfection, 0.0, 1.0)
	return out
