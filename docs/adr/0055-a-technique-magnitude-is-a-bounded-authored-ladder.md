# 0055 A technique's magnitude is a bounded authored ladder, never the realm power table

- Status: Accepted
- Date: 2026-10-02

## Context

A technique's effect has to stay relevant from the first realm to the thirtieth. The realm ladder
spans 1.0x to 551.46x, so something has to scale or deep techniques are worthless.

Three ladders were available, and the repo already owns two of them.

- `core/realm_power_table.tres` — 1.0x to 551.46x, keyed by realm id. This is the *actor* table.
- `game/data/item_options/item_magnitude_scale.json` — 1.0x to 3.9x, linear, +0.1 per realm.
- A rate step, `RATE_STEP = 1.02` per path.

AGENTS.md already states the governing rule for a third number: a rate must not outrun the
authored per-realm work budget, or the deep realms get cheap. Measured against the actual seeds,
the binding floor is **qi's `progress_required` at R29 to R30: 1.035714**. Body and mind are
looser at 1.047619 and 1.048417. The floor for a shared ladder is qi's.

The three paths have genuinely different shapes. Qi is exactly linear in ordinal
(`100 * max(1, R-1)`). Mind is a power law, `100 * (R-1)^1.45`, which fits all 30 realms to the
rounding digit. Body accelerates, roughly `exp(0.0449*i + 0.00393*i^2)`. Body's deep-realm price
inflates 8.75x faster than qi's, so no single ladder tracks all three.

## Decision

- **A technique's magnitude rides its own authored per-realm ladder**, separate from both
  existing tables, because it measures a third thing: neither an actor's strength nor a relative
  item upgrade.
- **The ladder is geometric, not linear.** A linear ladder's step shrinks as a percentage of a
  rising base, so a linear ladder is shortest exactly where the rule bites hardest. The existing
  item table fails the floor by 0.9-2.1% *at R29 to R30 specifically*. A constant ratio satisfies
  the floor everywhere once it satisfies it at the deep end.
- **The step is at or below 1.035714**, the measured minimum work-budget step, giving about
  **2.77x across the whole ladder**. This is a magnitude, not a power: it sits two orders of
  magnitude below the 551x table.
- **Never `realm_power_table.tres`.** That table already scales the actor's own attack and defense
  stats. A technique on that ladder would multiply 551.46x by 551.46x and put ~304,000x on one
  skill. Reusing an actor-magnitude table for a bonus is the category error ADR 0050 exists to
  prevent.
- **Each path carries its own copy**, like `RATE_STEP`, because a module may reach another module
  only through its facade and the alternative is a shared curve. Retune all three together.
- **Grade is a floor, not a scale.** A technique's authored grade decides the minimum realm; it
  never multiplies the effect.

## Numbers

**The ladder.** `TECHNIQUE_STEP = 1.035714` (= 29/28, qi's own deep step), authored per realm
id like `realm_power_table.tres`, one entry per realm, R1 at 1.0. Span `1.035714^29 =
2.7667`; per tier `^9 = 1.3714`; two tiers `1.8807`. The actor table steps `1.2432` per realm.
`MAG_GRADE` multiplies it by grade — mortal `1.0`, spirit `1.6`, earth `2.2`, heaven `3.2`,
immortal `4.5`, divine `6.5` — so the ladder's span is what a grade band crosses.

**Mastery — 5 rungs.** Per rung power `x1.15`, qi cost `x0.94`, cooldown `x0.96`, compounding:

| Rung | power | qi cost | cooldown | qi throughput |
|---|---|---|---|---|
| 0 | 1.000 | 1.000 | 1.000 | 1.000 |
| 1 | 1.150 | 0.940 | 0.960 | 1.223 |
| 2 | 1.323 | 0.884 | 0.922 | 1.497 |
| 3 | 1.521 | 0.831 | 0.885 | 1.831 |
| 4 | 1.749 | 0.781 | 0.849 | 2.240 |

In **grade bands** (one = a single tier's span, `^9` = `1.3714`; the two-tier span
is `^18` = `1.8807`): rung-4 raw power `1.749` = **1.28 bands**, just under the `1.37`
the ladder grants per tier; rung-4 qi throughput `1.749/0.781 = 2.240` = **1.63
bands**, so the technique that keeps its cost down wins the fight; per-rung `1.15` =
**0.84 bands**, so five rungs buy less than the 4.26 bands a whole tier grants and
mastery is never a substitute for advancing. Rung-4 cost `0.781` and cooldown `0.849`
both clear `0.5` — a rung that halves output is a trap rung.

**Learning cost — per path, like `RATE_STEP`, not shared.** `LEARN_STEP = 1.03`,
`LEARN_BASE = 100.0`; at ordinal `i` price = `100 * 1.03^i * MAG_GRADE` (R1 mortal `100`,
R30 divine `1531.77`). `1.03 <= 1.035714` with 0.55% headroom and it also clears the authored
`29/28 = 1.037037`, so DEF-0084's generator drift cannot push it above the floor. Span
`1.03^29 = 2.3566` against `2.7667` of measured work growth: study is cheaper than a
breakthrough everywhere and never runs ahead of it. The step is deliberately not the floor
itself, which leaves the margin explicit. Drift `(1.035714/1.03)^29 = 1.174`.

## Consequences

- Deep techniques stay relevant while costing real progress, so technique mastery never becomes
  the cheapest path to power in the game.
- The ladder is a third per-realm table. AGENTS.md must name it as deliberate, alongside the
  existing pair, so a future agent does not "reconcile" it with the other two.
- Because the step is sized to qi's floor, body and mind finish roughly 28-30% cheaper relative
  to their own budgets. Given the 8.75x shape divergence that is the least-bad direction, and
  per-path ladders make it tunable later without touching this decision.
- The ladder needs a shape guard like `realm_power check`: one entry per realm id, R1 at 1.0,
  strictly rising, and every consecutive ratio at or below the ceiling.