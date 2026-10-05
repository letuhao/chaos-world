# Rate stats must use PERCENT, never FLAT

Status: accepted
Date: 2026-10-02

## Context

`Stat.Op` has FLAT, PERCENT and MULT, and `ItemDef` stores `flat_modifiers` and
`percent_modifiers` as free-form dictionaries. Nothing declared which stats may
use which op.

`core/actor_stats.gd` reveals that stats are not uniformly scaled:

- fraction-scaled with a hard cap: `crit_chance` (0.05, cap 0.75), `evasion`
  (cap 0.6), `status_resistance` (cap 0.8), `cooldown_reduction` (cap 0.4),
  `qi_cost_reduction` (cap 0.5)
- multiplier-scaled, where 1.0 means "no change": `attack_speed` (cap 2.5),
  `cultivation_rate`, `insight_gain`, `breakthrough_chance`
- flat magnitude: `max_health`, `max_qi`, `max_stamina`, `attack_*`, `defense_*`,
  `poise`, `move_speed`, the `*_regen` family

`_put` applies `(base + flat) * (1 + percent)`, so a FLAT modifier on a
fraction-scaled stat is added after the cap is computed and is never clamped.
Flat `status_resistance=10` on a base of ~0.1 yields 10.1 — 1010% resistance.

Content generation hit this repeatedly: 80 modifiers across 56 items used FLAT
on a rate stat, including `cultivation_rate=50` (51x) and
`status_resistance=26` (2600%).

## Decision

Declare the classification in the schema, where the stat ids already live, and
let tooling read it rather than duplicate it.

`contracts/stat.gd` gains `const RATE_STATS`, listing the fraction- and
multiplier-scaled ids with the baselines that justify each. The schema is the
single source of truth; the tooling follows it.

`tools data distribution` treats a FLAT modifier on any `RATE_STATS` id as an
**error**, and flags zero-valued modifiers as a warning.

## Consequences

- The existing 80 offenders were migrated to `percent_modifiers`, dividing by 100
  to preserve the evident authorial intent ("+10" meant +10%).
- Generators must read `RATE_STATS` before choosing a modifier kind. A cap does
  not save a bad value: `_put` applies FLAT after the cap is computed.
- Adding a stat to `RATE_STATS` immediately extends the audit; no tool change.
- A stat absent from `RATE_STATS` is treated as flat magnitude. Adding a new
  fractional stat without listing it here is the failure mode to watch for.

## Alternatives rejected

- **Document the rule in prose only.** Already failed in practice; nothing
  enforced it for 1500+ items.
- **Hardcode the list in `tools/data.py`.** Duplicates schema knowledge and
  drifts when a stat is added or reclassified.
- **Clamp FLAT rate-stat values at runtime.** Hides the content error instead of
  surfacing it, and silently discards the intended magnitude.