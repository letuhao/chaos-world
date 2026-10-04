class_name SaveClock
extends RefCounted

## Counts whole periods and says when a save is due (ADR 0128).
##
## ## Why this is a counter and not a timer
##
## DEF-0111: nothing may read `Time.get_ticks_*`, declare `_process` or call `get_tree()`.
## A wall-clock deadline inside persisted state is a recorded defect in this repo —
## `body_cultivation/attempt.gd` names an attempt by wall-clock time and it became a DIFFERENT
## attempt after every reload. So the schedule is an absolute tick count decremented by the same
## delta the world already consumes, and it is never persisted.
##
## ## Why the schedule is unseeable
##
## Because a save can only land on a period boundary the player never sees, "when saving
## happens" is decided entirely by periods. That is the requirement, not a limitation: the
## player has no save button and no choice about when the game writes.

## Whole periods between autosaves. A save can therefore only happen after at least one full
## period has elapsed, which is what makes the schedule invisible rather than arbitrary.
const AUTOSAVE_PERIODS := 12

## Seconds of world time in one period. **This is the SSOT's ratio and it is declared here
## only until the clock migration moves it** (ADR 0171): `app/world_pulse.gd` holds
## `PERIOD_SECONDS := 120.0` for the world clock, and this file held a copy that was never
## read, so the two could not drift because neither was used.
##
## Read through [method pull] and never inlined, because the bug this replaces was a
## schedule that counted CALLS. `pull(delta)` incremented `_periods` by one per invocation
## and discarded `delta` entirely, so at 60fps the autosave fired every 12 frames — about
## 0.2 seconds — while its own docstring promised "whole periods" and `AUTOSAVE_PERIODS`
## said 12. A clock that writes to disk, twelve times a second, on the user's machine.
const PERIOD_SECONDS := 120.0

var _periods: int = 0
var _elapsed: float = 0.0
var _dirty: bool = false
var _saves: int = 0


## Turn elapsed seconds into whole periods and report whether a save is due.
##
## **Arithmetic, not a call count.** A period count is a division of the accumulated
## seconds by [constant PERIOD_SECONDS], and the remainder is carried — this file is a
## clock, not the world clock, so banking the remainder here is correct: it is the same
## conversion buffer `WorldPulse._elapsed` is (`app/world_pulse.gd:127-129`), and the
## world's own rule that surplus is DROPPED applies to the world fold, not to a converter
## whose job is to be exact.
##
## Returns true at most once per `AUTOSAVE_PERIODS`, and resets the counter so the next
## one is a full period away rather than the remainder of this one.
func pull(delta: float) -> bool:
	if delta <= 0.0:
		return false
	_elapsed += delta
	var periods := int(_elapsed / PERIOD_SECONDS)
	if periods <= 0:
		return false
	_elapsed -= float(periods) * PERIOD_SECONDS
	_periods += periods
	if _periods < AUTOSAVE_PERIODS:
		return false
	_periods = 0
	return true


## Mark the world as changed. A dirty world is worth saving sooner than a quiet one, and the
## flag is how a beat, a claim or a purchase can make a save due without the clock guessing.
func mark_dirty() -> void:
	_dirty = true


## Whether anything has changed since the last save.
func is_dirty() -> bool:
	return _dirty


## Record that a save happened, clearing the dirty flag. Called after a successful write only,
## so a FAILED save leaves the world dirty and the next period tries again.
func record_saved() -> void:
	_saves += 1
	_dirty = false


## How many saves this clock has recorded. A probe asserts the policy without touching disk.
func saves() -> int:
	return _saves


## Forget everything. Used when a new game starts, so a fresh run does not inherit a previous
## one's schedule — including the carried remainder, which is a fraction of a period of the
## PREVIOUS body's time and would otherwise fire the first autosave of the new game early.
func reset() -> void:
	_periods = 0
	_elapsed = 0.0
	_dirty = false
	_saves = 0
