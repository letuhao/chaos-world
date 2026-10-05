# 0179 the autosave is period-driven, not wall-clock driven, and the clock stops converting seconds

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0173 (the clock is one SSOT; time-shaped constants migrate to `TimeLadder`), ADR 0128 (autosaved envelope, the schedule is periods and the player never chooses), ADR 0089 / DEF-0111 (the caller owns time)

## Context

`SaveClock.pull(delta)` was the LAST accrual verb in the tree still handed a frame delta. It took `delta: float`, divided accumulated seconds by its own `PERIOD_SECONDS`, and carried the remainder.

Two measured defects, one fix:

- **It counted CALLS, not periods.** `pull` incremented `_periods` by one per invocation and ignored `delta`, so at 60fps the autosave fired every 12 frames — about 0.2 seconds, twelve disk writes a second on the player's machine — while its own docstring promised whole periods and `AUTOSAVE_PERIODS` said 12. Fixed earlier this session (divide by `PERIOD_SECONDS`, carry the remainder; tests in `tests/modules/save/test_save_envelope.gd`).
- **It held a private copy of the base ratio.** `save_clock.gd:34` declared `PERIOD_SECONDS := 120.0` beside the canonical one, the same disease as ADR 0116's `*RealmProfile` curves: numerically identical, green under every value assertion, invisible to `tools arch` (`BARE_REF_UNITS` excludes `modules/*`). ADR 0173 names this as the pending half of its migration.

ADR 0173 then deleted the premise: **there is no real-time clock for the world.** Idle is frozen, the world moves only when the player acts, and combat's real seconds enter as an explicit period count. A converter that turns seconds into periods is therefore a converter with nothing left to convert — the autosave was a wall-clock holdout the program's own rule no longer permits.

## Decision

**The autosave turns NOT realtime. `SaveClock` counts whole periods and nothing else.**

- **`pull(delta)` becomes `advance(periods: int)`** — an accrual verb like every other one here, taking an explicit whole-period count from the caller that owns time. Same bounds as before: a non-positive count is neither a boundary nor an error, and the counter resets at the boundary so the next save is a full schedule away.
- **The seconds conversion is DELETED, not moved.** `PERIOD_SECONDS` is gone from this file. It declares no ratio at all, so "a fraction of a period" is not expressible as input — which is the property that makes the old call-count bug unrepresentable rather than merely fixed.
- **Surplus is DROPPED, never banked.** `advance(13)` resets rather than leaving one period owed, for `world_pulse.gd:90-94`'s reason: a banked surplus is a backlog that pays out at a rate nobody chose.
- **The periods come from the SAME explicit path the world fold uses.** `ItemWorkbenchPlay.advance_world` calls `WorldPulse.advance_periods(periods)` and then hands the autosave how many periods the world ACTUALLY moved — the delta of the fold's own running total against the last one seen, so `MAX_PERIODS_PER_PULL`'s clamp is what the save is told, not what the caller asked for. `advance_one_period` routes through it. There is no second accrual path and no frame callback.
- **`mark_dirty` / `is_dirty` are DELETED.** They had no production caller and no reader anywhere in the tree. With saves riding period boundaries there is nothing for a manual dirty flag to do: the schedule IS the trigger, and `record_saved` already clears on a successful write. Giving it a caller would be inventing a save-sooner-than-the-schedule rule nothing else in the program has; leaving dead code in a file whose whole subject is one rule is worse.
- **`item_workbench_app.gd`'s `_process` no longer calls `poll_save(delta)`.** The frame driver keeps `poll_death()`; the save moved to the action path with everything else.
- **A guard pins it.** `test_no_shipped_caller_drives_the_autosave_from_a_frame_delta` scans `res://src` CODE for `poll_save(delta)` or `clock.pull(`, and `test_the_autosave_is_fed_by_the_world_fold_and_nothing_else` names the one caller that must remain. The first is RED until `item_workbench_app.gd:628` drops the call — which is that file's change, not this one.

## Consequences

- **A save can now only land where the player acts.** No idle autosave, by construction and by decision — the same rule that froze idle for the world.
- **The schedule is unseeable still, and for a stronger reason.** Before, the boundary was hidden behind a ratio; now there is no ratio to hide behind, only a count.
- **`poll_save` is period-driven but a public verb.** It stays reachable by a headless probe or a test without a frame driver, which is what makes the schedule assertable at all.
- **A state change that crosses no boundary waits up to `AUTOSAVE_PERIODS`.** Accepted: it is the requirement, not a regression. A death still saves immediately (`poll_death`).
- **`tests/core/test_time_ladder.gd` and `test_time_ladder_single_source.gd` need their known-copies pin narrowed** — `save_clock.gd:34` is named there as a pending duplicate and is now gone. Those are `core/` test files, outside this change.