# A modifier on a stat nothing backs is applied, not discarded

`ActorStats` resolves a modifier only where something else already wrote the stat.
`_recompute` writes a fixed list of core ids and `_ensure_providers` writes whatever
providers contribute; `derived(id)` then answers from `_provider_cache`, else from
`_derived.get(id, 0.0)`. A `StatModifier` on any other id was read, bucketed, and
thrown away.

## Why it was wrong

`CombatStats.RATE_IDS` — `accuracy`, `parry.rate`, `reflect.resist.rate` and six more —
has no core entry and no provider: `CombatStats` is a constants class, not a
`StatProvider`. So every one of those ids read `0.0` no matter what an author wrote on
it. The modifier was on the actor and never applied.

ADR 0068 asks every rate channel to ship a shape test asserting a `FLAT` modifier at a
`0.0` baseline is non-zero, and that test failed on all nine ids. It was right to.

## The rule

After the core derived stats, back every remaining modifier bucket at `0.0` through the
same `_put` formula.

This preserves the ADR 0022 trap rather than papering over it. A `FLAT` reads
`(0.0 + v) * 1 = v`. A `PERCENT` still reads `(0.0 + 0.0) * 1.25 = 0.0`, which is why
`CombatStats.RATE_DEFAULTS` is all zeros and why a percentage must never be able to
conjure a rate out of nothing. A flat addition is an authored number and was always
legal; it was being dropped.

## Consequence

A stat only exists once something authors it — a base, a derived formula, a provider,
or a flat modifier. Reading one that nobody has authored still answers `0.0`; it is
simply no longer impossible to *write* one.