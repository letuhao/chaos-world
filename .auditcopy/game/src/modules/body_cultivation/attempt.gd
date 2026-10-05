class_name BodyAttempt
extends RefCounted

## A body-cultivation breakthrough attempt (ADR 0015/0023/0028). One record per
## attempt: identity, costs, the preparation it was committed against, trial
## progress, and the granted outcome. Only one attempt may be active per actor;
## the resolved record is kept so its outcome cannot be granted twice.
##
## The award is keyed on this record's identity, never on the path's progress:
## `outcome_granted` is the single once-only guard. `resolve_attempt` adds the
## realm seed's rewards with `stats.set_base(id, get_base(id) + reward)`, a
## cumulative write keyed on nothing else — so without this flag a second
## resolve of the same record would pay the award again.
##
## The resolved record is NOT cleared. `start_attempt` refuses only on an
## *active* attempt, so a terminal record stays readable (which realm was
## fought for, what it paid) without blocking the next attempt.

const STATUS_PENDING := &"pending"
const STATUS_COMMITTED := &"committed"
const STATUS_SUCCESS := &"success"
const STATUS_FAILED := &"failed"
## Abandoned before its trial ran (cancelled, superseded, or its gate went
## stale): nothing was rolled, so no deviation is owed and the realm is kept.
const STATUS_CANCELLED := &"cancelled"

## Statuses that end an attempt. `outcome_granted` is the outcome flag, not a
## status: a cancelled attempt resolved without one.
const TERMINAL_STATUSES: Array[StringName] = [
	STATUS_SUCCESS,
	STATUS_FAILED,
	STATUS_CANCELLED,
]

var attempt_id: StringName = &""
var actor_id: StringName = &""
var path_id: StringName = &""
var source_rank: StringName = &""
var target_rank: StringName = &""
var seed_id: StringName = &""
var status: StringName = STATUS_PENDING
var pill_consumed: bool = false
var costs_paid: bool = false
## The preparation the attempt was committed against. The roll reads its
## `chance`, never a re-evaluation: an attempt that spans a save must resolve
## against the body it paid for, not against whatever the huyệt look like on
## reload.
var preparation: Dictionary = {}
var trial_complete: bool = false
var outcome_granted: bool = false
## The seed the roll is taken from, drawn once at commit and replayed at resolve
## (`BodyAttemptRoll`). This is the number a save has to carry for a
## save-spanning attempt to resolve as it was paid for rather than as the body
## happens to look on reload.
##
## It is never 0 in a record this build wrote: seed 0's first draw is 0.202272,
## below every `chance_base` on the ladder, so it WON every attempt on every realm —
## which is what this field used to hold whenever the caller passed no generator, and
## it made every body breakthrough a certain success with the deviation loop
## unreachable. 0 survives here only as the default of a fresh record and in payloads
## written before that fix; `BodyAttemptRoll.replay` reproduces those exactly rather
## than re-rolling an attempt the player already committed.
var rng_state: int = 0
## Per-actor attempt counter. Makes the id stable and reproducible instead of
## wall-clock derived, so a save reload still names the same attempt — the old
## `Time.get_ticks_msec()` id named a *different* attempt after every reload.
var sequence: int = 0


func _init(
	p_attempt_id: StringName = &"",
	p_actor_id: StringName = &"",
	p_path_id: StringName = &"",
	p_source_rank: StringName = &"",
	p_target_rank: StringName = &"",
	p_seed_id: StringName = &""
) -> void:
	attempt_id = p_attempt_id
	actor_id = p_actor_id
	path_id = p_path_id
	source_rank = p_source_rank
	target_rank = p_target_rank
	seed_id = p_seed_id


func commit() -> void:
	status = STATUS_COMMITTED


func mark_trial_complete() -> void:
	trial_complete = true


func succeed() -> void:
	status = STATUS_SUCCESS
	outcome_granted = true


func fail() -> void:
	status = STATUS_FAILED


## End the attempt without a trial. No deviation, no award, realm kept.
func cancel() -> void:
	status = STATUS_CANCELLED


func is_active() -> bool:
	return status == STATUS_PENDING or status == STATUS_COMMITTED


func is_resolved() -> bool:
	return TERMINAL_STATUSES.has(status)


## Stable per-actor attempt id: same actor, same sequence, same id.
static func make_id(p_actor_id: StringName, p_path_id: StringName, p_sequence: int) -> StringName:
	return StringName("body_%s_%s_%d" % [p_actor_id, p_path_id, p_sequence])


func to_dict() -> Dictionary:
	return {
		"attempt_id": String(attempt_id),
		"actor_id": String(actor_id),
		"path_id": String(path_id),
		"source_rank": String(source_rank),
		"target_rank": String(target_rank),
		"seed_id": String(seed_id),
		"status": String(status),
		"pill_consumed": pill_consumed,
		"costs_paid": costs_paid,
		"preparation": preparation.duplicate(true),
		"trial_complete": trial_complete,
		"outcome_granted": outcome_granted,
		"rng_state": rng_state,
		"sequence": sequence,
	}


static func from_dict(data: Dictionary) -> BodyAttempt:
	var attempt := (
		BodyAttempt
		. new(
			StringName(data.get("attempt_id", "")),
			StringName(data.get("actor_id", "")),
			StringName(data.get("path_id", "")),
			StringName(data.get("source_rank", "")),
			StringName(data.get("target_rank", "")),
			StringName(data.get("seed_id", "")),
		)
	)
	attempt.status = StringName(data.get("status", STATUS_PENDING))
	attempt.pill_consumed = bool(data.get("pill_consumed", false))
	attempt.costs_paid = bool(data.get("costs_paid", false))
	var preparation: Variant = data.get("preparation", {})
	attempt.preparation = (preparation.duplicate(true) if preparation is Dictionary else {})
	attempt.trial_complete = bool(data.get("trial_complete", false))
	attempt.outcome_granted = bool(data.get("outcome_granted", false))
	attempt.rng_state = int(data.get("rng_state", 0))
	attempt.sequence = int(data.get("sequence", 0))
	return attempt
