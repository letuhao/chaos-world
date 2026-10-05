# 0051 mind-breakthrough-roll-reads-only-the-sea

- Status: Accepted
- Date: 2026-10-02
- Supersedes nothing. Extends ADR 0028 (the same defect class, fixed on the body path) and ADR 0031.

## Context

`MindAdvancement._chance` read `actor.stats.derived(Stat.BREAKTHROUGH_CHANCE)` plus the sea's clarity:

```gdscript
clampf(actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + sea.clarity * 0.5, 0.05, 0.95)
```

Core derives that stat as `0.1 + comprehension * 0.01 + will * 0.005`, and comprehension IS this path's entry gate (`comprehension_required`). ADR 0028 records precisely this hazard on the body path and fixed it there by refusing to read the stat; the mind path read it anyway.

At attempt time comprehension is already at or above `comprehension_required`, which reaches 66 at R5. So the gate's own floor plus clarity evaluated past the 0.95 clamp at R4 -> R5 and stayed pinned there: **25 of the 29 boundaries were guaranteed successes.** Consequences:

- `_deviate` was unreachable above R4, so a failure was never a failure.
- `MindTraining.recover` and every authored `recovery_item` were unreachable above R4 — the ADR 0031 content existed and could not be spent.
- `MindAttempt.STATUS_FAILED` and the whole recoverable-deviation loop were dead content on most of the ladder.

Nothing failed. Every unit test passed, because each asserted the mechanism rather than the distribution of outcomes.

## Decision

`_chance` reads the sea's clarity and nothing else:

```gdscript
clampf(MIN_CHANCE + sea.clarity * CLARITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)
```

The rule, stated once so it cannot be re-derived wrongly: **the breakthrough roll must not read a quantity the entry gate already pins.** A gate input is a precondition, not a difficulty dial. Where a path wants a second, non-circular input it must be one the gate does not already constrain.

Clarity is safe as the sole input because it is bounded twice: `SeaOfConsciousness.set_clarity` clamps to 1.0, and `MindTraining.cultivate` caps it at the CURRENT realm's own `clarity_required`. The sum therefore cannot reach `MAX_CHANCE` at any realm, so cultivating harder buys a sharper sea rather than a certain breakthrough.

`MIN_CHANCE`/`MAX_CHANCE`/`CLARITY_TO_CHANCE` are named constants, and the tests read them rather than restating 0.05/0.95/0.5.

## Consequences

- Every one of the 29 boundaries now has a rollable failure. The deviation and recovery loops are live content again.
- `tests/modules/mind_cultivation/test_mind_breakthrough_chance.gd` pins the invariant at all 29 boundaries: the chance never reaches the ceiling at a legal pre-state, and does not move with comprehension past the gate.
- Restoring the old formula fails 163+ assertions in that suite, including at R4 -> R5.
- **qi_cultivation reads the same stat with the same hazard** (`qi_cultivation/advancement.gd`, `qi_cultivation/breakthrough_transaction.gd`) and is out of scope here. Its entry gate is not comprehension, so it is not yet proven broken, but it is the same shape.