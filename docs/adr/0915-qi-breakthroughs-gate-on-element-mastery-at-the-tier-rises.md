# 0915 Qi breakthroughs gate on element mastery at the tier rises

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0004's second half is the elemental mastery path: ranks gate element tiers and "master elements to rise". The path shipped (practice, Awaken, the injected labour curve, the rank+realm door), but nothing about the QI climb read it — a body could leave mortality, become an immortal and reach Transcendence without ever opening an element. The mastery loop was a parallel progression, not a requirement.

The owner's ruling: qi realm breakthroughs gate on mastery. The plan's shape: authored element requirements at chosen qi rungs, enforced and previewed through the same predicate (ADR 0044).

## Decision

- **`element_mastery_required`** (`game/src/modules/qi_cultivation/realm_seed.gd:55`) — the total `element_mastery_<e>` summed across every element that entering this realm demands. `0.0` is the authored "no gate"; the field is authored content like `required_channel_refinement` (the qi seed generator does not emit it — the shipped qi seeds already carry fields the generator under-emits and the seed writer refuses to regenerate them, DEF-0084's protected state).
- **The gate sits at the TIER RISES**: `spirit_condensation`, `earth_immortal`, `transcendent` — the first realm of each tier above mortal. Every other realm carries `0.0`, so the mortal ladder is untouched.
- **Each rise asks for its own realm's `progress_required`** (900 / 1800 / 2700), which is the same number the elemental climb pays to reach the rung the qi climb is entering. The two ladders already share one rate (ADR 0116/0268); this shares one number, and no new balance surface exists to drift.
- **One predicate**: `QiRealmSeed.element_mastery_met(total_mastery)` — `QiBreakthroughCondition.can_breakthrough` enforces it, `QiBreakthroughTransaction.preview` reports `insufficient_element_mastery` (`game/src/modules/qi_cultivation/breakthrough_transaction.gd:70`) through it, and `execute` re-validates the whole condition set. The three cannot disagree (ADR 0044), the same rule `channel_met` follows.
- **The read is the facade's**: `_elements_ready` (`game/src/modules/qi_cultivation/breakthrough_condition.gd:23`) preloads `res://src/modules/elements/api.gd` and calls `ElementsApi.total_mastery(actor)`; the seed never learns where mastery lives. This adds a `qi_cultivation -> elements` edge to `tools/arch/registry.json` (acyclic: `elements` depends on `contracts`/`core` only).
- **The test probe earns the gate through the public verbs** (`ElementsApi.awaken` opens a spark, `ElementsApi.practise` raises mastery at the shared rate), so the qi ladder's boundary audits measure a state a player can hold.

## Consequences

- The elemental path becomes MANDATORY at three points: a pure qi body must bank element mastery before each rise. That is the ruling's intent, and the gates are deliberately at rises rather than every realm so the ladder between them stays a choice.
- A qi climb that never trains elements now stops at `tribulation` (R9), visible in `preview`'s `unmet_conditions` as `insufficient_element_mastery` and refused by `execute`.
- The elemental path's own advance is not gated by qi, so the coupling is one-way by design: elements can run ahead, qi cannot.
- Re-authoring the qi seeds through the generator would silently drop the gate (and `required_channel_refinement`, and both catalysts) — the protected-state hazard DEF-0084 records, unchanged by this ADR.
