# 0088 Status potency reuses element_power and mastery stays a penetration lever

- Status: Proposed
- Date: 2026-10-03

## Context

The damage doc recommended **Option B**: a new per-element family
`element_status_power_<e>` beside `element_power_<e>` in
`modules/elements/stats.gd:24`, contributed by `ElementProvider`. The status doc
recommended **rejecting** it: `element_power_<e>` is already the realm-invariant
elemental magnitude channel (ADR 0069), and a `status_power_<e>` would be a second
magnitude vocabulary for the same element.

Measured, Option B costs 10 more authored option ids and one more per-element channel
at every read site — precisely what ADR 0068 declined to pay for nine defensive
families, for the reason that one family read and nine siblings unread is a shipped
defect class (Keepverse D14).

Mastery already has exactly one meaning, and ADR 0069 fixed it: a **penetration**
lever, `mastery_pen`, subtracted before the clamp so it can never amplify past
`RESIST_CAP`. Two questions have to be settled and they are different questions.

## Decision

- **Potency is a REUSE, not a new channel: it reads `element_power_<e>`,** the same id
  `ElementProvider.contribute` already emits
  (`modules/elements/provider.gd:23`). Potency is a fraction of the elemental term the
  hit actually landed, so it inherits ADR 0069's realm-invariance fix (the
  `RealmScaling.SOURCE` MULT on that id) with **no new id, no new option record, and no
  new read site.** ADR 0069's measured element fraction — 0.7619 at R1 falling to 0.0058
  at R30 — stops being a status-layer defect the moment it reuses the same scalar.
- **Option B stays a documented escape hatch, not a decision.** If a balance pass ever
  needs a great elementalist who is a weak debuffer, it is one new prefix in
  `stats.gd` beside `POWER_PREFIX` and one `contribute` line — additive, and then its
  own ADR with a shape test.
- **Mastery does exactly two things, both penetration:** it subtracts from the
  defender's elemental resistance (S12) and, in ADR 0069's damage formula, from theirs.
  It **never gates a status by name** and adds no second ladder: a status is unlocked by
  its element's tier (`ElementMastery.can_use`, `modules/elements/mastery.gd:26-31`) and
  by authoring it on a technique. `MAX_ELEMENT_TIER := 3` and `can_use` are untouched.
- **The realm modifier must not be applied twice.** ADR 0069 already records that
  `ElementsApi.attach` "must not be called twice on one actor" because
  `ActorStats.add_provider` appends unguarded (`core/actor_stats.gd:48-51`). A status
  layer that re-attaches `ElementProvider` reintroduces that defect.
- **If the new id is ever added, `Stat.RATE_STATS` is the wrong place for it and a
  shape test is mandatory.** `RATE_STATS` (`contracts/stat.gd:73`) is hand-written
  over **static** core ids and `tools/data.py:1208` resolves it by regex over that same
  file, so a *dynamic* per-element id is invisible to both. ADR 0068's rule applies
  verbatim: derive the rate shape, author `op: FLAT`, ship a shape test.

## Consequences

- Zero new stat ids, zero new authored item options, zero new per-element read sites —
  the reuse is why this is cheap enough to decide now rather than after a balance pass.
- **The cost of the reuse, stated:** status potency and element damage scale off one
  knob, so a player cannot be a great elementalist and a weak debuffer. That is an
  accepted trade now and a cheap one to reverse later.
- `ElementMastery.path_def()` is still called by tests only
  (`tests/modules/elements/test_element_mastery.gd:8`) and `ElementsApi.attach` has no
  production caller, so `element_power_<e>` is derived for **nobody** in the running
  game. S12 therefore reads a stat that is `0.0` everywhere until the mastery path and
  `app/` wiring land — a known dependency, not a new decision.
- This ADR does not touch ADR 0069's tier-2 dominance defect: `ElementDefaults.advanced()`
  still has empty `generates` on every entry
  (`modules/elements/default_elements.gd:20-24`), so the `TIER_MASTERY_STEP` divisor is
  still owed and still lands in `ElementProvider`, not in combat.
