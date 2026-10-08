# 0937 the additive core-owned contribution is an opt-in the re-emit family declares

- Status: Accepted
- Date: 2026-10-09
- Closes: part of DEF-0384's reconciliation (correction to ADR 0934)
- Depends on: ADR 0002 (stat providers), ADR 0026 (a provider replaces the baseline it emits), ADR 0934 (the pools ride both curves)

## Context

ADR 0934 landed the pool/damage reconciliation, and one of its bullets — "a provider
contribution for a core-owned stat is an ADDITION, applied once" — was implemented as a
universal rule in `ActorStats._ensure_providers`. That is exactly right for the family the
bullet was measured on: `BodyProvider` shapes the four shared combat stats by emitting a
BONUS on top of core's value, so the addition is what keeps the core baseline alive
(ADR 0026) without bucketing the realm multiplier twice.

It is wrong for every OTHER provider, and the qi family measured the damage the moment the
rule went universal: a provider's contribution for an id core also seeds is usually that
provider's OWN formula for the id, not a bonus on core's. The qi provider's
`qi_absorption` (`(qi_affinity*0.5 + spirit*0.2) * (1+meridian)`) and the dantian's
`dantian_capacity` (`effective_capacity()`) are REPLACEMENT baselines under ADR 0026, and
adding them to core's figure double-counted them: absorption 12 → 19 (+7), dantian
capacity 100 → 200 (+100), qi family 10775 → 10768.

## Decision

- **The addition is an OPT-IN the provider declares.** `StatProvider.adds_to_core()`
  (contracts, default `false`); `BodyProvider` overrides it to `true`; `_ensure_providers`
  applies the additive branch only for a provider that opted in.
- **Replacement remains the default and is unchanged** (ADR 0026): a contribution for an
  id is bucketed exactly once from its own value, flats applied, whether or not core also
  seeds that id. A provider that wants the additive shape says so.

## Consequences

- The contract gains one method with a non-breaking default; every existing provider keeps
  its measured behavior.
- The re-emit family stays additive: the body bonus lands once, no `power^2`.
- Guard: the qi family's absorption/capacity suites and the actor-vs-actor census (flat
  23 heavy / 192 rapid) pin both sides — a provider that flips the flag without a bonus
  shape, or one that needs it and does not declare it, turns one of them red.
