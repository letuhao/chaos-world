# 0022 damage-reduction uses flat not percent

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0011

## Context

ADR 0011 put every stat whose baseline is a fraction or a multiplier into `RATE_STATS`, on the rule that a FLAT modifier on such a stat is a content error.

`core/actor_stats.gd` resolves a stat as `(base + flat) * (1 + percent)`. Every other `RATE_STATS` entry has a non-zero baseline, so PERCENT is meaningful for them. `DAMAGE_REDUCTION` is the exception:

```gdscript
_put(Stat.DAMAGE_REDUCTION, 0.0, flat, percent, mult)
```

With a baseline of `0.0`, a PERCENT modifier evaluates to `(0.0 + 0.0) * (1 + p) = 0.0` for every value of `p`. PERCENT on `damage_reduction` is therefore a guaranteed no-op, and ADR 0011 made it the only legal flag.

44 items carried a percent `damage_reduction` modifier that granted nothing at all. The content was wrong and the contract that validated it was wrong in the same direction, so the audit stayed clean.

## Decision

- Remove `DAMAGE_REDUCTION` from `RATE_STATS`. Its baseline is zero, so PERCENT carries no meaning and FLAT is the only form that can work.
- Convert the existing percent `damage_reduction` modifiers to FLAT, preserving intent:
  - value `<= 1.0` -> FLAT at the same number (the author already wrote a 0..1 fraction).
  - value `> 1.0` -> FLAT at `value / 100` (the author wrote a percentage, e.g. `8.0` meant 8%, not 800%).
- Keep the ADR 0011 invariant that still holds and is the real content rule: **PERCENT is always valid on any stat; only FLAT on a rate stat is wrong.**

## Consequences

- `Stat.RATE_STATS` is defined by baseline, and the invariant to preserve when editing it is **"the baseline is not identically zero"** — not "conceptually a rate". The baselines in `actor_stats.gd` fall into two shapes, and only the first is safe:
  - A constant term guarantees a non-zero baseline regardless of the actor: `crit_chance` (`0.05 + ...`), `crit_damage` (`1.5 + ...`), `attack_speed` (`1.0 + ...`), `cultivation_rate` (`1.0 + ...`), `insight_gain` (`1.0 + ...`), `breakthrough_chance` (`0.1 + ...`).
  - An attribute-only baseline is zero whenever the governing attribute is zero: `evasion` (`minf(0.6, agility * 0.0015)`), `cooldown_reduction` (`minf(0.4, comprehension * 0.002)`), `qi_cost_reduction` (`minf(0.5, aptitude * 0.001)`), `status_resistance` (`minf(0.8, will * 0.003)`). PERCENT is meaningful for these in normal play, but degrades to a no-op for an actor whose attribute is 0. They stay in `RATE_STATS` because their cap term makes flat the worse error.
  - `damage_reduction` (`0.0`) has neither. That is the whole bug.
- A FLAT `damage_reduction` above 1.0 means more than 100% mitigation. `actor_stats.gd` floors derived stats at 0 but sets no ceiling, so an over-large value is clamped by nothing. The distribution audit's power-curve check is the guard against this, not the schema.
- `tools data audit` cannot catch this class of bug on its own: it validates the flag against the contract, and the contract was what was wrong. A future stat added to `RATE_STATS` with an identically-zero baseline reintroduces the same silent failure. The cheap guard is to derive `RATE_STATS` membership from the baselines in `actor_stats.gd` rather than restating it by hand.