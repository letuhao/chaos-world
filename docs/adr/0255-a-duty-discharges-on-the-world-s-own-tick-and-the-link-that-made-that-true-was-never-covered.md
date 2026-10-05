# A duty discharges on the world's own tick, and the link that made that true was never covered

Closes DEF-0196 by measurement rather than by addition. No `core/` change, no
`SectApi` change, and no new verb.

## Status

Accepted.

## Context

**DEF-0196's headline measurement is stale.** The deferred row records
`InstitutionClaim.owe` and `.settle` as having ZERO production callers. Re-measured
on this tree, that is no longer true:

- `SectDuty.serve` (`sect_duty.gd:117`) calls `claim.settle(term, periods)`, and is
  dispatched from `institution_resolver.gd:341`'s `serve_duty` arm, which is reached
  from `WorldPulse._advance` → `_settle_institutions` (`world_pulse.gd:550`) on every
  advance. `game/src` has no `.owe(` caller at all — debt is opened by writing the
  claim's `obligation` map directly (`member_obligation_lines`, `open_office`), never
  by calling `owe`.
- `tools gate_reach report` now reads `oaths_discharged` as **"repeatable: writer
  called from production code"**, with 0 findings.

ADR 0145 closed the first half of this (the verb existed with no caller). What was
left was a chain of three links with **one of them unobserved**:

```
WorldPulse._advance  ->  InstitutionResolver.settle  ->  SectDuty.serve
```

## Decision

**Keep the wiring; cover the hop that nobody was watching.**

Measured by mutation, on `tools test --suite sect`, baseline `1555 passed, 0 failed`:

| Mutation | Result |
|---|---|
| **A** — sever `_settle_institutions(periods, _crossed)` in `world_pulse.gd` (guard `if periods < 0`) | **1555 passed, 0 failed — unchanged** |
| **B** — `institution_resolver.gd`'s `serve_duty` arm returns `false` | 1512 passed, **11 failed** |

Mutation A is the finding. Cutting the production path from the ledger was free: the
tick was the missing link, and a green suite said nothing about it. Mutation B shows
the verb underneath is genuinely covered, so the gap is precisely this one hop.

`game/tests/app/test_world_tick_discharges_obligation.gd` drives the real composition
root — `WorldPulse.new(actor, BeatDirector.new()).advance_periods(1)` — and asserts the
debt clears and `oaths_discharged` moves. It lives in `tests/app/` because what it
measures is `app/`'s tick.

**Why not a new verb.** The moment already exists and is the right one: a member
serving out a term as the world runs. ADR 0145's reasoning stands — `SectApi` is at
`MAX_FACADE_PUBLIC_METHODS` and a 13th public verb would fail `tools arch`.

## Consequences

- **Both halves are proven on shipped content.** NON-TRIVIAL: the fixture installs a
  sect at `min_purity = 0` (which is `jade_court.tres` exactly), so `join` opens
  `duty_t_house` alone and `summary()["settled"]` is false at join. SATISFIABLE: the
  only office is a `bare_position`, whose `succession_method` is not walkable, so
  nothing outranks serving and one elapsed period discharges it — no press, no
  intervening verb.
- **Idempotence is asserted, not assumed.** Three further ticks after a cleared debt
  leave both the owed figure and the fact count byte-identical: a settled claim
  proposes `{}`, so `serve` is refused with `nothing_owed` and records nothing.
- **`settle` cannot make debt worse.** `InstitutionClaim.settle` returns `mini(owed,
  periods)` and clamps at zero; a term is only recorded on the CROSSING
  (`claim.owed(term) <= 0` read after the write), so `oaths_discharged` counts TERMS,
  never periods.
- The suite borrows `SectFixtureCatalog` from `tests/modules/sect/` and restores the
  shipped catalog in `teardown`; the catalog singleton is SHARED, so a suite that
  installs and never restores hands every later suite a different world.
- **Deferred, not fixed:** the four `destiny` counters mapped from these facts stay at
  0, because `DestinyProjection.on_beat_earned` is reached only from
  `BeatDirector.offer` and module-owned producers bypass it by design (ADR 0145).
  Unverified here.