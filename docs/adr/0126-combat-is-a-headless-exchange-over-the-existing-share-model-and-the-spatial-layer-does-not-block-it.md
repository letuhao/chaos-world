# 0126 Combat is a headless exchange over the existing share model, and the spatial layer does not block it

- Status: Proposed
- Date: 2026-10-03
- Re-measures: DEF-0058, which is open and whose stated evidence is stale
- Re-measures: ADR 0123, correct on both models and wrong on one caller claim

## Context

- DEF-0058 claims `CharacterBody2D`, `Camera2D` and `Input.is_action` occur zero
  times in all of `src/`, and that `CombatApi` exposes only `attach_shield`/`shield`.
  Both are false against the tree.
- `player_adapter.gd:2` extends `CharacterBody2D`; `:37` and `:57` name
  `Camera2D`; `:117-123` call `Input.is_action_pressed`.
- `modules/combat/api.gd:50-87` exposes seven methods — `exchange`, `player`,
  `preview`, `duel`, `resolve_share`, `offense`, `guard`. `Shield` and
  `attach_shield` were deleted by ADR 0076 and appear nowhere in `src/`.
- `CombatApi.exchange` is reachable: `ui/screens/loot_encounter.gd:124`.
- The player CAN die today. `exchange.gd:364-378` spends `share * health.maximum`
  and calls `LootApi.abandon` at zero, returning `player_lost`.
- The damage spine IS partly wired, against ADR 0123's stronger claim.
  `app/item_workbench_app.gd:358` calls `CombatEngineApi.breakdown` from
  `_resolve_technique_hit`, installed at `:332` as the `TechniqueCasting` resolver.
- `CombatEngineApi.bind_mechanism` still has zero callers in `src/` AND in
  `tests/`; every suite binds through `MechanismSlot.bind` directly. So
  `MechanismSlot.of` would assert for any real actor on that live path.
- `world_stage.gd:13` claims `WorldEntry` is a base script no scene extends. Eight
  shipped scenes extend it, including `scenes/domains/mortal_plains.tscn`.
- `app/input_handler.gd` does not exist. Input handling is
  `PlayerAdapter._unhandled_input` plus the `[input]` map in `project.godot`.

## Decision

- **The slice uses the SHARE model (`modules/combat`); the spine is not adopted
  for it.** `CombatDamage.resolve_hit` already computes an exchange, has a
  production caller, decrements a real pool, and terminates a run.
- **The spatial layer does not block combat.** `PlayerAdapter` stays unmounted.
  Combat resolves over two `Actor`s and needs no node, no body and no frame.
- **The gap is the second party, not a damage formula.** `CombatApi.exchange`
  answers only for a boss `loot` already spawned. One new facade verb resolves a
  single blow actor-to-actor through the same `CombatDamage` function, so no
  third model appears.
- **`bind_mechanism` gains a production caller in `app/`**, the only layer allowed
  to name a concrete mechanism. This retires the live assert on the
  technique-casting seam as a side effect.
- **`PlayerAdapter.attack` (`:156-164`) is where an injected attack callable
  lands.** The adapter already carries the state enum and signal; it gains none.

## Consequences

- The player gains a real failure state: a defeated actor has health at zero and
  the caller sees it through a named refusal, not only loot's run ledger.
- `WorldStage` and `PlayerAdapter` stay unreachable in production. That is now a
  recorded deferral rather than an unrecorded gap.
- ADR 0123's "no production entry point" bullet is partly wrong and is superseded
  on that point only; its two-model conclusion stands unchanged.
- DEF-0058 should be re-worded, not closed: combat has runtime and lacks a world
  to fight in.
- Nothing here binds `BodyDamage` or `MindDamage`; ADR 0070/0071 stay design only.
- No `.tscn` change, no `run/main_scene` change, no scene tree needed to test.