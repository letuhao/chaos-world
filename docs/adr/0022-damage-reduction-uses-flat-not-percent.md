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

- `Stat.RATE_STATS` is defined by baseline, and a zero baseline disqualifies a stat from it. The invariant to preserve when editing `RATE_STATS` is "non-zero baseline", not "conceptually a rate".
- A FLAT `damage_reduction` above 1.0 means more than 100% mitigation. `actor_stats.gd` floors derived stats at 0 but sets no ceiling, so an over-large value is clamped by nothing. The distribution audit's power-curve check is the guard against this, not the schema.
- `tools data audit` cannot catch this class of bug on its own: it validates the flag against the contract, and the contract was what was wrong. A future stat added to `RATE_STATS` with a zero baseline reintroduces the same silent failure. The cheap guard is to derive `RATE_STATS` membership from the baselines in `actor_stats.gd` rather than restating it by hand.