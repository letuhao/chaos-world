# 0899 the soul block is a pool a rate and an anchor repair

- Status: Accepted
- Date: 2026-10-07

## Context

- The ledger's soul rows were `new`: the soul module already carried `integrity` /
  `integrity_max` in its injected store, and `SoulApi.repair` / `AnchorApi.repair` already
  moved them — but nothing published the soul as an actor STAT, so no build could move them
  and the Thần Sinh cell measured thinnest in the distribution.
- The owner directed "ship new sub features for the incomplete systems if need" and the
  ledger built the sockets; this ADR fills the first one.

## Decision

- `SoulStats` owns three ids and `SoulProvider` publishes their NEUTRAL baselines:
  `soul_integrity` `100.0` (= `SoulState.DEFAULT_INTEGRITY`), `soul_recovery` `0.0` (no
  passive recovery ships), `soul_anchor` `1.0` (= the shipped anchor amount). ADR 0897's
  discipline: authored sockets that are byte-identical until something writes them.
- `SoulApi.attach` attaches the provider once (guarded like `FertilityApi._has_provider`,
  because `add_provider` appends unguarded) and raises the stored `integrity_max` to the
  actor's `soul_integrity` when the stat is above it — ONE WAY: a falling stat never lowers a
  ceiling already granted, because a soul shrunk below a life it survived would be a second
  death the rules did not ask for.
- `SoulApi.recover(actor, periods)` restores `floor(soul_recovery * periods)`; explicit
  periods and no clock (DEF-0111), and it refuses `no_recovery` until content authors a rate.
- `SoulApi.anchor_factor(actor)` returns the `soul_anchor` multiplier (`1.0` when absent or
  non-positive); `AnchorApi.repair` multiplies it INSIDE its single floor, so the shipped
  factor restores exactly the amount the anchor restored before the stat existed.

## Consequences

- The soul cell can now be fed by L1 primaries and by content without another mechanism
  change; the three ledger rows moved `new` -> `exists`.
- Byte-identity at the baselines is pinned by `tests/modules/soul/test_soul_stats.gd`, and
  the anchor/soul suites keep their amounts because `1.0` and `0.0` are the shipped
  behaviours.
- `reincarnation_memory` and `soul_age` remain `new` rows: they need content, not mechanism.
