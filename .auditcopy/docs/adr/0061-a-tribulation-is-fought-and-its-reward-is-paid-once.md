# 0061 A tribulation is fought, and its reward is paid once

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0041 (outcome is decided and durable), ADR 0050 (authored, id-keyed)
- Resolves: DEF-0052 (the remainder), DEF-0066

## Context

ADR 0041 gave a tribulation an explicit outcome and four entry points, and claimed
it made resolve idempotent. Reading the code behind that claim found five defects,
none of them visible from the outside:

1. **Nothing outside a test could start a fight.** `begin_tribulation` /
   `advance_tribulation` / `resolve_tribulation` / `cancel_tribulation`
   (`core/breakthrough.gd:77-145`) had no production caller, so `tribulation_ok`
   (`core/breakthrough.gd:60`) was a wall for R19+ on every path.
2. **The verdict came from the caller.** `resolve_tribulation(actor, success)` took a
   `bool` and had no roll: `advance_wave` only flipped a phase enum. `Tribulation`
   had no way to fight itself. `_apply_failure` could therefore not run from
   production — all five `apply_result` call sites passed a literal `true`, so
   defeat, meridian damage, dantian damage and dao-heart damage were dead content
   and every item serving them had no live path to it.
3. **The reward was paid twice.** `survived()` is true only after
   `apply_result(success=true)`, which also called `_apply_rewards`, and `apply_result`
   had no once-guard: the fight paid, and then the breakthrough that consumed the
   survivor paid again. Entering R19 granted 70 insight for a 35-insight fight and
   stacked two `heavenly_blessing` statuses. `resolve_tribulation` was not idempotent
   either — ADR 0041 says it "requires an unresolved, complete record"; it guarded
   only on `is_complete()`. No test covered a double resolve, which is the gap ADR
   0041 assumed was covered.
4. **Preparation was never populated, and the condition that read it could never
   pass.** `start()` priced the fight from `preparation` and cleared it on the next
   line, so the branch only ever saw the *previous* fight's aid; and
   `TribulationCondition` required `formation`, `pill` or `artifact` keys that
   nothing in `src/` ever writes — a permanently-false guard in the codebase.
5. **The rating was positional.** `_compute_waves` was `3 + ladder.index_of(id) / 4`,
   so inserting a realm moved every tribulation above it: the exact coupling ADR
   0050 removed from `realm_power_table.tres`, reintroduced one file away.

## Decision

- **The fight is driven by the gate it opens.** `Breakthrough.face_tribulation`
  (`core/breakthrough.gd:112`) is the production entry point: every path's
  breakthrough action calls it before it validates anything. One call advances
  **one wave**, so the tribulation is an encounter with turns, and it returns true
  **only when the gate was already open when the call arrived**. A survivor is
  therefore produced by one call and consumed by the next, which is what keeps the
  gate from requiring an artifact the same call makes. Rejected: fighting the whole
  tribulation inside the advance (circular — the gate would consume what that call
  just produced), and a dedicated facade verb (`qi_cultivation` and
  `body_cultivation` sit at the 12-method ISP cap, and `ui/` must not own a rule).
- **The outcome is a roll.** `Tribulation.fight_wave` (`core/tribulation.gd:137`)
  charges `WAVE_TOLL` of dao-heart strain per wave and, on the wave that ends the
  fight, rolls once against `endurance()` (`core/tribulation.gd:162`), which falls
  linearly with the rating between `MIN_ENDURANCE` and `MAX_ENDURANCE` — never
  certain, never a coin flip. The roll is an injected `rng`, so tests choose it.
- **The reward belongs to the fight.** `apply_result` returns early when the record
  is already decided (`core/tribulation.gd:183`), and the five post-advance
  `apply_result(actor, true)` calls are deleted: a breakthrough consumes a survivor,
  it does not manufacture one.
- **Preparation is measured, and it prices the fight.** `start` reads `formation`
  (the share of channels developed past merely open) and `environment` (the inside
  world's stability) off the actor *before* rating them
  (`core/tribulation.gd:279`), sums only the named `PREPARATION_AIDS`, and caps the
  reduction at `PREPARATION_FLOOR`. It is an input, never a gate.
- **The rating is keyed.** `WAVES_BY_TIER` (`core/tribulation.gd:51`) is resolved
  through the realm id's tier, with `BASE_WAVES` for an id the ladder has never
  heard of. Rejected: a 30-entry per-realm table — no guard owns it, and the ladder
  is append-only data while a wave count is Tribulation's own rating, like
  `TYPE_PRESSURE`.
- **`TribulationCondition` is deleted**, not deprecated: the real gate is
  `Breakthrough.tribulation_ok`, and a second gate nothing can satisfy is worse than
  no second gate. **`Tribulation.TRIBULATION_REALM_THRESHOLD` is deleted** as a
  second copy of `Breakthrough.IMMORTAL_REALM_THRESHOLD`.
- **`resolve_tribulation` stays** as the explicit-verdict hook for a caller that
  already knows the outcome, now genuinely idempotent; production decides by roll.

## Consequences

- R19-R30 are reachable by play on all three paths, and a lost tribulation is a real,
  recoverable state: nothing is dead by deletion, because `_apply_failure` and the
  failure items are now live. The only things this ADR removes outright are
  `TribulationCondition`, its test, and the duplicated threshold constant.
- A refused attempt at R19+ now mutates the actor — it fights a wave. That is the
  one disclosed exception to ADR 0044's "a refusal leaves the actor byte-for-byte as
  found": nothing is *granted* on that path and no pill is consumed.
- `difficulty`, `max_waves`, `endurance` and `preparation` are all derived from the
  tier and the actor, so a resumed fight must not re-derive them: `to_dict`
  (`core/tribulation.gd:210`) is the single serialization point and the record is a
  snapshot of the price paid.
- **Deferred / handed off:** no facade or screen exposes the fight yet, so a panel
  cannot render "wave 3 of 7, endurance 0.7" and a player meets the tribulation by
  pressing the breakthrough action. That wiring belongs to `ui/` and to whichever
  module wants a dedicated verb; `core` needs nothing further to offer.
- Untouched and still open: `QiAdvancement.try_breakthrough` and
  `QiBreakthroughTransaction.execute` remain near-duplicates (ADR 0036 leaves the
  consolidation open), and only the second validates before granting (ADR 0044).