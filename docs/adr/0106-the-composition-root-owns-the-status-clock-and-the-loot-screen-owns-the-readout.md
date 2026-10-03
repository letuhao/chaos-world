# 0106 The composition root owns the status clock and the loot screen owns the readout

- Status: Proposed
- Date: 2026-10-03
- Extends: ADR 0089 (the tick caller and the purge), read against ADR 0056

## Context

ADR 0089 named the composition root as the tick caller and said `app/` would call
`tick_statuses` "from the same `InputHandler.tick` that already drives the frame
(`app/input_handler.gd:120-125`)". **That file no longer exists** — ADR 0056 deleted the
`SkillSystem` prototype it belonged to. `StatusLoop` was built as the wire to hang off it
(`app/status_loop.gd:56`) and therefore has no caller either. The game has no per-frame
driver in its shipped composition root.

`ItemWorkbenchApp.tscn` composes a nav bar and a screen stack and nothing else, and
`item_workbench_app.gd` declares no `_process`/`_physics_process`. `PlayerAdapter._physics_process`
(`app/player_adapter.gd:79`) is a real `CharacterBody2D` callback but is mounted by **no
`.tscn` in the repo** — DEF-0098 lists `player_adapter` among the verified orphans. So the
brief's premise, that `PlayerAdapter` is "a real driver in the running game", is wrong: it
is real code with no scene.

That leaves two true statements: the tick needs a caller, and the composition root is the
only layer allowed to invent one.

## Decision

**The tick caller is a `_process` on the composition root, `app/`, calling
`StatusLoop.tick(delta)`. `delta` is always a parameter and never a clock read. The readout
is `ui/screens/loot_encounter.gd`, and `status` is added to `rules.UI_MODULES`.**

- **`item_workbench_app.gd` gains `_process(delta) -> StatusLoop.tick(delta)`** for the
  app's own actor, and nothing else. This satisfies ADR 0089's rule ("the tick caller is
  the composition root") and ADR 0056's ("`app/` wires; it does not implement it") without
  putting rules in `app/`: `StatusLoop` (`app/status_loop.gd:56`) already owns no state and
  already delegates to `StatusApi.tick_statuses`.
- **The `delta` rule, stated so it cannot drift: whoever owns time passes it.** The
  composition root passes the engine's `delta`. A headless test passes its own. Nothing
  anywhere reads `Time.get_ticks_*` — ADR 0089 forbade the wall clock, and
  `StatusRegistry.tick` (`core/status_registry.gd:93`) already documents `delta` as
  "ALWAYS a parameter". `StatusLoop.tick` keeps its signature and stays a no-op on a null
  actor.
- **The boss gets nothing, and that is correct rather than a gap.** `loot` owns the boss as
  a `Dictionary` in module data (`modules/loot/loot_state.gd:523-547`), not an `Actor`, so
  it has no `statuses` array to tick. ADR 0074's `ActorFactory.spawn_npc`
  (`app/actor_factory.gd:67`) is the shape that fixes it, and when a boss becomes an
  `Actor` the same `StatusLoop.tick` call covers it with no change here. Declining a boss
  status now is a consequence of ADR 0076, not a new decision.
- **`exit_combat()` already exists and needs no caller yet.** `StatusLoop.exit_combat`
  (`app/status_loop.gd:66`) purges COMBAT-scope statuses per ADR 0089; the loot screen's
  `act_leave` is where it belongs once a player can hold one, and it is wired in the same
  change that makes the readout visible.
- **The readout is `StatusApi.summary(actor)`, rendered by the loot screen's existing
  fight panel.** `summary` (`modules/status/api.gd:163`) is already primitives-only per
  AGENTS.md's screen contract, and `LootEncounterScreen` already owns the fight readout
  through `LootBossPanel.show_fight` (`ui/panels/loot_boss_panel.gd:60`) called from
  `loot_encounter.gd:370`. The screen passes the dict to the panel and the panel owns every
  `%d`; no number formatting is added to a screen (AGENTS.md:151).
- **`status` is added to `rules.UI_MODULES` with no module deps.** This is the real
  constraint and it is a one-line change: `status` is registered in `registry.json` but was
  **absent** from `UI_MODULES`, so any `ui/` file naming `StatusApi` today fails
  `enforce.py:160-163`. It is granted with `[]` because a readout is a pure read of the
  facade and the status module reads no other module.
- **The composition root, not `ui/`, is the caller.** `ui/` is a pure consumer
  (AGENTS.md:146) and a `_process` there would be a second clock. The rule that survives
  this ADR is one sentence: **one tick caller, in `app/`, passing an explicit `delta`.**

## Consequences

- `Actor.tick_statuses` (`core/actor.gd:157`) gains its first production caller, which is
  the exact finding ADR 0089 recorded as unfixed, and `StatusApi.tick_statuses`
  (`modules/status/api.gd:106`) gains its second.
- `app_state_warnings` still does not fire: `item_workbench_app.gd` gains a
  `_process` (one `tick-loop` signal) and holds no member array or persistence call, and
  `APP_STATE_MIN_SIGNALS` is 2 (`enforce.py:44`). ADR 0056's boundary is preserved by the
  gate rather than by convention.
- `enforce.py:398-422` stops reporting `status` as a permission granted to nothing once the
  module has a directory — it already does; the change here is that `ui/` may now spend it.
- The contract test is a delta, not a population: `StatusLoop.tick` with no actor is a
  no-op refusal; a status past its `tick_interval` spends exactly one pulse per interval
  owed; a screen's `summary()` carries the active ids and stays primitives-only.
- A second frame driver is the named failure. Any future caller that wants to tick statuses
  calls `StatusApi.tick_statuses` on a `delta` it was given, and does not add a `_process`
  to `game/src/` outside `app/`.