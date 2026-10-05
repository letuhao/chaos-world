class_name SaveClock
extends RefCounted

## Counts whole periods and says when a save is due (ADR 0128, ADR 0179).
##
## ## Why this is a counter and not a timer
##
## DEF-0111: nothing may read `Time.get_ticks_*`, declare `_process` or call `get_tree()`.
## A wall-clock deadline inside persisted state is a recorded defect in this repo —
## `body_cultivation/attempt.gd` names an attempt by wall-clock time and it became a DIFFERENT
## attempt after every reload.
##
## ## Why there is no seconds here at all
##
## **The autosave is NOT realtime.** It is an accrual verb like every other one in this
## program, and an accrual verb takes an EXPLICIT WHOLE PERIOD COUNT from the caller that owns
## time (ADR 0089 / DEF-0111, ADR 0179). This file used to hold its own copy of the period
## ratio; that copy is gone, because a second number that measures time is how the schedule
## came to count CALLS rather than periods in the first place. Nothing here knows how long a
## period is — only how many have been handed down.
##
## ## Why the schedule is unseeable
##
## Because a save can only land on a period boundary the player never sees, "when saving
## happens" is decided entirely by periods. That is the requirement, not a limitation: the
## player has no save button and no choice about when the game writes.

## Whole periods between autosaves. A save can therefore only happen after at least one full
## period has elapsed, which is what makes the schedule invisible rather than arbitrary.
const AUTOSAVE_PERIODS := 12

var _periods: int = 0
var _saves: int = 0


## Take `periods` whole periods from the caller that owns time and report whether a save is
## due. **A count, never a duration** (ADR 0179).
##
## Returns true at most once per [constant AUTOSAVE_PERIODS], and resets the counter so the
## next one is a full period away rather than the remainder of this one.
##
## **Surplus is DROPPED, never banked**: `advance(13)` resets the counter rather than leaving
## one period owed, because a banked surplus is a backlog that pays out at a rate nobody chose
## (`app/world_pulse.gd:90-94`). Twelve periods and a third are not a third of a save.
##
## A non-positive count is a caller that elapsed nothing, which is neither a boundary nor an
## error.
func advance(periods: int) -> bool:
	if periods <= 0:
		return false
	_periods += periods
	if _periods < AUTOSAVE_PERIODS:
		return false
	_periods = 0
	return true


## Record that a save happened. Called after a successful write only, so a FAILED save leaves
## the next boundary free to try again.
func record_saved() -> void:
	_saves += 1


## How many saves this clock has recorded. A probe asserts the policy without touching disk.
func saves() -> int:
	return _saves


## Forget everything. Used when a new game starts, so a fresh run does not inherit a previous
## one's schedule.
func reset() -> void:
	_periods = 0
	_saves = 0
