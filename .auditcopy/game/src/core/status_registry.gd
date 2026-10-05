class_name StatusRegistry
extends RefCounted

## One actor's statuses, and the rules that merge a re-application onto the single
## instance already carrying that id (ADR 0086).
##
## These rules live HERE rather than on `Actor` because they are the shared
## vocabulary every status obeys: combat's S12, ADR 0075's environment zones and a
## consumable pill all go through `Actor.add_status`, and a merge rule that lived
## on the actor would be the place a fourth kind of status re-derives it.
## `Actor` keeps the array, the signals and the delegate; this owns the merge.

## A status applied for the first time, or an existing one changed.
signal status_added(status_id: StringName)

## One resolution happened, in whichever of the three modes `stacking` names.
signal status_merged(status_id: StringName, outcome: StringName, stacks: int)

## A `tick_interval` came due. The status is DATA: the listener decides what one
## pulse is worth, because the combat module's damage formula stays the only one
## and `core/` may not name it.
signal status_ticked(status_id: StringName, magnitude: float)

## The four merge outcomes and the one refusal. A legitimate resolution is never
## a refusal: the outcomes are named in `outcome`, so "merged into the existing
## one" cannot be mistaken for "did nothing".
const APPLIED := &"applied"
const REFRESHED := &"refreshed"
const STACKED := &"stacked"
const REPLACED := &"replaced"
const REFUSED := &"refused"

## The keys every answer carries. `ok` and `reason` are the two `StatusApply`
## already reads off whatever `add_status` returns
## (`modules/combat_engine/status_apply.gd:526-543`), so this answer is that shape
## and not a new one; `outcome` and `stacks` are what a caller needs to tell a
## refresh from a stack.
const OK := &"ok"
const STATUS_ID := &"status_id"
const OUTCOME := &"outcome"
const STACKS := &"stacks"
const REASON := &"reason"

const REFUSE_NULL := &"status is null"
const REFUSE_NO_ID := &"status id is empty"

## The one instance per id, held by REFERENCE to the actor's own array rather than
## a shadow copy of it: `FertilityApi.advance` erases `actor.statuses` directly
## and `EnvironmentField._status` reads it directly, so a second array here would
## go stale the moment either ran.
var statuses: Array[StatusEffect] = []


func _init(p_statuses: Array[StatusEffect] = []) -> void:
	statuses = p_statuses


## Apply `status`, merging it onto the instance that already carries that id.
## `actor` is read only for `mark_stats_dirty()`, so a merge invalidates derived
## stats exactly as an append does.
func apply(actor: Actor, status: StatusEffect) -> Dictionary:
	if status == null:
		return _answer(REFUSED, &"", 0, REFUSE_NULL)
	if status.id == &"":
		return _answer(REFUSED, &"", 0, REFUSE_NO_ID)
	var index := _index_of(status.id)
	if index < 0:
		statuses.append(status)
		_dirty(actor)
		status_added.emit(status.id)
		return _answer(APPLIED, status.id, status.stacks, &"")
	var outcome := _merge(index, status)
	_dirty(actor)
	status_merged.emit(status.id, outcome, status.stacks)
	return _answer(outcome, status.id, status.stacks, &"")


## The live instance carrying `status_id`, or null. The read four call sites were
## each writing out for themselves, as one method that cannot drift from the
## merge rule that decides which instance survives.
func find(status_id: StringName) -> StatusEffect:
	var index := _index_of(status_id)
	return statuses[index] if index >= 0 else null


## Advance every status by `delta`: drain the timer, pay out each interval that
## came due, and remove what expired.
##
## Returns `{removed: [StringName], ticks: [{id, magnitude}]}` rather than
## emitting, because `Actor` owns the signals its listeners connected to and
## relaying them from here would be a second emitter for the same event.
##
## `delta` is ALWAYS a parameter and never a wall-clock read — a status that read
## the clock itself would tick differently on a replay than under a test, and
## nothing here touches an `rng` either. A DOT's magnitude is whatever was
## authored on it.
func tick(actor: Actor, delta: float) -> Dictionary:
	var removed: Array[StringName] = []
	var ticks: Array = []
	if delta > 0.0:
		for index in range(statuses.size() - 1, -1, -1):
			var status := statuses[index]
			status.tick(delta)
			status.tick_elapsed += delta
			# One entry per pulse, not per frame: a hitched frame owes the status
			# every interval it crossed, or a DOT silently under-pays exactly when
			# the game is already behind. No interval means no pulse at all.
			for _pulse in _pulses_due(status):
				ticks.append({&"id": status.id, &"magnitude": status.magnitude})
			if not status.is_expired():
				continue
			statuses.remove_at(index)
			removed.append(status.id)
	if not ticks.is_empty():
		_dirty(actor)
	for status_id in removed:
		_dirty(actor)
	return {&"removed": removed, &"ticks": ticks}


# --- the merge -----------------------------------------------------------------


## Resolve `status` onto the held instance at `index`, and name what it did.
##
## ## `magnitude_cap <= 0.0` means UNCAPPED
##
## A cap is authored data, and a def that authors none should compound rather than
## resolve to zero — the silent clamp to nothing is the worse failure.
##
## ## REPLACE swaps the instance rather than mutating it
##
## Overwriting a held instance's fields in place would leave a `PregnancyStatus`
## holding a REPLACE status's numbers, i.e. a state machine wearing another
## status's data. Handing the array the incoming object instead is the only merge
## whose result is exactly what the caller applied — and it is still ONE instance
## per `(actor, status_id)`, which is the invariant the array has to keep.
func _merge(index: int, status: StatusEffect) -> StringName:
	var held := statuses[index]
	match status.stacking:
		StatusEffect.Stacking.STACK:
			held.remaining = maxf(held.remaining, status.remaining)
			held.magnitude = _capped(held.magnitude + status.magnitude, held.magnitude_cap)
			held.stacks = maxi(held.stacks + 1, 1)
			held.tick_interval = maxf(held.tick_interval, status.tick_interval)
			return STACKED
		StatusEffect.Stacking.REFRESH:
			held.remaining = maxf(held.remaining, status.remaining)
			# The STRONGER magnitude, never the newer one: a weak re-application
			# must not shorten a strong one. That asymmetry is the whole rule.
			held.magnitude = maxf(held.magnitude, status.magnitude)
			held.tick_interval = maxf(held.tick_interval, status.tick_interval)
			return REFRESHED
		_:
			statuses[index] = status
			return REPLACED


func _capped(magnitude: float, cap: float) -> float:
	return magnitude if cap <= 0.0 else minf(magnitude, cap)


## How many pulses `status` owes, draining its interval as it counts. The
## accumulator carries the remainder, so a frame boundary that lands mid-interval
## does not lose or double-pay it. A status with no interval pays nothing: a
## blessing and a pregnancy are timers, not clocks.
func _pulses_due(status: StatusEffect) -> int:
	if status.tick_interval <= 0.0:
		return 0
	var pulses := int(floor(status.tick_elapsed / status.tick_interval))
	status.tick_elapsed = fmod(status.tick_elapsed, status.tick_interval)
	return pulses


## Where `status_id` sits, or -1. Bounded `for` over the actor's status list,
## which [method tick] keeps pruned.
func _index_of(status_id: StringName) -> int:
	for index in statuses.size():
		if statuses[index].id == status_id:
			return index
	return -1


## An actor mid-construction has no stats, and a status applied to nothing is not
## worth a crash; a caller that wants the refusal reports it there.
func _dirty(actor: Actor) -> void:
	if actor != null and actor.stats != null:
		actor.mark_stats_dirty()


func _answer(
	outcome: StringName, status_id: StringName, stacks: int, reason: StringName
) -> Dictionary:
	return {
		OK: outcome != REFUSED,
		STATUS_ID: String(status_id),
		OUTCOME: outcome,
		STACKS: stacks,
		REASON: String(reason),
	}
