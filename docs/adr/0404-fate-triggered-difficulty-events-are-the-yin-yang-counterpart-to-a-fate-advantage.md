# 0404 Fate-triggered difficulty events are the yin-yang counterpart to a fate advantage

- Status: Accepted
- Date: 2026-10-06
- Consistent with: ADR 0065 (fate is earned, never removed), ADR 0129 (difficulty scalars)

## Context

A fate grants a permanent advantage: +crit_chance, +attack, +cultivation_rate. The yin-yang
rule in AGENTS.md requires every advantage to carry its counterpart. Today a fate grants
power with no cost — the advantage is unpaired, which is a design defect, not a feature.

The difficulty system (ADR 0129) is a set of player-facing scalars selected by the player.
Fate-triggered difficulty events are different: they are earned, not selected, and they
make the world harder as a consequence of the fate's advantage.

## Decision

- **`FateDef.difficulty_events`** is an array of event dictionaries authored on the fate.
  Each event has `event_type` (closed vocabulary), `magnitude` (float), and `description`
  (player-facing text). Three event types: `enemy_spawn`, `social_difficulty`,
  `combat_difficulty`.
- **Events are earned, not selected.** A difficulty event activates when its fate is earned
  and deactivates never — the earn-only invariant (ADR 0065) applies. There is no revoke
  path, no reset, no debug tool.
- **The difficulty event engine** (`difficulty_event_engine.gd`) reads all held fates,
  collects their difficulty events, and computes a total difficulty modifier per event
  type. It is a pure read from the ledger — no state is stored.
- **Yin-yang pairing is enforced by a gate.** Every fate with positive stat modifiers
  MUST declare at least one difficulty event. A fate with no modifiers needs no event
  (pure-narrative fates are legitimate). The gate is a GDScript test that walks the
  catalog and fails on an unpaired advantage.
- **The difficulty modifier is a multiplier on the existing difficulty scalars.** It does
  not add a new power curve — it scales what the player already has. A fate with
  `enemy_spawn` magnitude 0.5 increases enemy spawn rate by 50%.

## Consequences

- The fate advantage is now paired: +crit_chance comes with harder enemies, +attack
  comes with stronger combat, +cultivation_rate comes with social difficulty.
- The difficulty event engine is a pure function from the ledger to a modifier
  dictionary. It stores nothing, so it cannot drift from the ledger.
- The yin-yang gate is a test, not a runtime check. It runs in `tools test` and fails
  the build on an unpaired advantage.
- The difficulty modifier is consumed by the combat engine and social system through
  the destiny facade, not by reaching into the destiny module directly.
