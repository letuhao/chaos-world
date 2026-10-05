# 0035 High-tier anchors are committed by the breakthrough, not required by it

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0028 ("No unguarded advance"), ADR 0018-0021 tier gates

## Context

`Breakthrough.tier_gates_met` required, for any target at index >= 18, a completed
tribulation *and* a stable inside world. Nothing in gameplay could ever produce
either: the only assignment to `actor.inside_world` in `src/` was the save-load
path in `actor.gd`. The Mind path escaped the gate because `MindBreakthroughCondition`
substitutes its own `MindAnchor.stage_met` policy, which requires the *previous*
tier's anchor. Body and Qi had no substitute, so they were hard-stopped at R18 and
R19-R30 was reachable only by tests writing success flags by hand — which
contradicted the traversal test's own header.

The gate was also circular in principle: entering R19 both required and produced
the Seed inside world, so no actor could satisfy it even with a creation action.

## Decision

- **`WorldAnchor` (`core/world_anchor.gd`) owns the shared schedule.** A successful
  breakthrough into index 18/21/24 commits the Seed/Pocket/Inner inside world; 27
  commits the Micro world and begins ascension; 29 commits the Great world and
  completes it. `commit` is idempotent.
- **Gates are offset by one tier.** `inside_world_ok` now delegates to
  `WorldAnchor.stage_met`, which requires milestones committed *strictly before*
  the target index. Entering R19 commits the Seed world; R20 is the first realm
  that requires it. `world_ok` and `ascension_ok` are relaxed the same way.
- **Tribulation stays a true prerequisite.** It is fought before the breakthrough,
  so unlike the anchors it is not the realm's own outcome. It also remains bound
  to the realm it was fought for (ADR 0032 concern in `tribulation_ok`).
- **Body and Qi commit through their existing success paths.** `BodyAdvancement`
  (both `resolve_attempt` and `try_breakthrough`) and `QiAdvancement` /
  `QiBreakthroughTransaction` call `WorldAnchor.commit(actor, target.index)` after
  a confirmed advance.
- **The qi breakthrough transaction validates.** `QiBreakthroughTransaction.execute`
  is the production entry point (`QiCultivationApi.attempt_breakthrough`), so it now
  runs `QiBreakthroughCondition` and `try_advance_gated` instead of consuming the
  pill and advancing blind. Without this, two calls in one frame advanced two realms
  on one pill with no progress, quality, channel, or tier check.

## Consequences

- Body and Qi reach R30 through public actions, so `test_full_traversal.gd` no
  longer needs to forge `InsideWorld` / `WorldState` / `AscensionState`.
- The schedule is now written down once in `core` instead of being implied by three
  different policies; Mind keeps its richer `MindAnchor` stages on top.
- `test_qi_breakthrough_transaction.gd` pins the validate-before-consume contract.
- Remaining and deliberately unchanged: `Tribulation.advance_wave()` still has no
  production caller, so the tribulation itself is still inert (tracked separately).
