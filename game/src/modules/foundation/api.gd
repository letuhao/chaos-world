class_name FoundationApi
extends RefCounted

## Public facade for the `foundation` module. Other modules may reference ONLY this file
## (`api.gd`).
##
## ## What this module is
##
## The SHARED half of the foundation program (BL-0951 / ADR 0939): the record of how
## perfectly each realm was left, and the vocabulary around it. Each cultivation path
## implements its own rules over the record — its own `min_foundation` demand, its own
## tribulation scaling, its own principle-based measurement — so no path keeps a second
## copy (ADR 0066) and this module never learns a path's formula.
##
## ## The one verb this slice publishes
##
## `snapshot` is the WRITE: called by a path's breakthrough transaction at the moment the
## actor leaves a realm. The reads (`foundation`, `state`, `summary`) land with the gate
## that consumes them — a published verb with no caller is the dead surface
## `tools/arch`'s caller-less guard refuses, and its allowlist is not a backlog.
##
## ## Three-state vocabulary (ADR 0083)
##
## A null actor or an empty realm answers a NAMED refusal, never a hidden zero.

const R_NO_ACTOR := "no_actor"
const R_EMPTY_REALM := "empty_realm"
const R_ALREADY_SNAPSHOTTED := "already_snapshotted"


## The carried aggregate the paths gate on: the mean of every snapshot, `0.0` when the
## actor has left no realm yet. This is the number a path's authored `min_foundation`
## compares against; the paths own the comparison, this module owns the arithmetic.
static func foundation(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return FoundationRecord.aggregate(
		FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	)


## The foundation a tribulation is fought at: the carried aggregate, or `1.0` when the
## actor has left no realm yet. An empty record is not a sloppy record — a fight the
## tribulation tests start at a realm directly has no departures to judge, so it rates
## the baseline rather than the harshest fight. A real climb always leaves realms behind
## it, so in play this default never fires; in a fixture it keeps the shipped endurance
## band exactly where the census measured it.
static func tribulation_foundation(actor: Actor) -> float:
	if actor == null:
		return 1.0
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if FoundationRecord.count(record) == 0:
		return 1.0
	return FoundationRecord.aggregate(record)


## Write the PERFECTION snapshot for a realm the actor is leaving. ONCE per realm: a
## second write for the same realm is refused by name, because a past the actor already
## spent must not be rewritable (ADR 0939).
##
## `perfection` is clamped into [0, 1]; an actor that never trained past its gate records
## `0.0`, which is a real answer rather than a missing one.
static func snapshot(actor: Actor, realm_id: StringName, perfection: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if realm_id == &"":
		return {"ok": false, "reason": R_EMPTY_REALM}
	var record := FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
	if FoundationRecord.has_snapshot(record, realm_id):
		return {
			"ok": false,
			"reason": R_ALREADY_SNAPSHOTTED,
			"realm": String(realm_id),
			"existing": FoundationRecord.snapshot_for(record, realm_id),
		}
	record = FoundationRecord.with_snapshot(record, realm_id, perfection)
	actor.set_module_data(FoundationRecord.SLOT, record)
	return {
		"ok": true,
		"realm": String(realm_id),
		"perfection": FoundationRecord.snapshot_for(record, realm_id),
		"count": FoundationRecord.count(record),
		"aggregate": FoundationRecord.aggregate(record),
	}
