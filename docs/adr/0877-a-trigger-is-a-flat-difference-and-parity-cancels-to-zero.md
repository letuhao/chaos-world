# 0877 a trigger is a flat difference and parity cancels to zero

- Status: Accepted
- Date: 2026-10-06

## Context

- Owner ruling 2026-10-06, on the combat pairs: every offence/defence pair is
  FLAT magnitudes with no cap; `attacker - defender` decides; equal totals cancel
  to exactly zero. The worked example: `1e10` crit rate against `1e10` crit
  resist reads `0%` crit. This reverses ADR 0215's ratio, which read `0.5` at
  parity and could never be pushed to certainty.
- The audit that preceded it found: `accuracy` was declared but never derived or
  authored anywhere, so no attack could beat any evasion; `parry`/`block` read
  the attacker's OWN `parry.rate`/`block.rate` in the suppress slot, so the
  break halves were dead; `crit_damage` shipped a `1.5 +` multiplier no defender
  could contest; `reflect.resist.damage` and `absorption` were declared and
  unread until ADR 0876 started the wiring.

## Decision

- One formula, written once (`CombatStats.rate_from_zero`), Keepverse's
  `RateFromZero`:
  `p = clampf(maxf(0.0, rate - resist) / scale, 0.0, 1.0)`.
  `delta <= 0` reads `0.0`; a non-positive `scale` reads `0.0` rather than
  dividing. NEITHER half is capped: `1e10` against `1e10` cancels at any
  magnitude. The `[0, 1]` is on the output only — probability arithmetic, not a
  progression ceiling (AGENTS.md: bound the output, never the input).
- The scale is DATA: `CombatTuning.rate_scale` (shipped `0.01`), reactivating the
  field ADR 0215 retired. Every trigger pair reads it: hit (accuracy vs evasion),
  crit (crit_chance vs crit_resist), parry (parry.rate vs parry.break), block
  (block.rate vs block.break), reflect (reflect.rate vs reflect.resist.rate),
  leech (lifesteal against nothing).
- Amount pairs read flat deltas rather than a trigger:
  `1 + rate_from_zero(crit_damage, crit_resist_damage)` for the crit multiplier
  (equal halves mean a cosmetic crit, never a penalty); the bounce share at the
  unit scale (both halves are already shares); `pierce` and the S7 factor keep
  their existing subtraction shapes.
- `accuracy` is DERIVED in core: `agility * 0.0015 + 0.005`. The base term is
  the attack's own accuracy, so a defender meets it by investing evasion rather
  than by the accident of both halves reading zero.
- `crit_damage` loses its `1.5 +` baseline (`comprehension * 0.004`) and leaves
  `RATE_STATS` with it; the two consumers that need a multiplier
  (`CombatDamage` via `CombatExchange.offense`/`CombatDuelHit._offense`) bank the
  bonus at the boundary onto that model's existing `1.5 +` reference, preserving its
  tuned numbers until the exchange lane converts to the flat pair.
- `CombatStats.contest` (the raw ratio) and `CombatBand.decisive` (the demoted
  sigmoid) are deleted. `CombatBand.rate`/`rate_of` read `rate_from_zero` over
  `tuning.rate_scale`.
- ADR 0215 is superseded; its properties are deliberately reversed: parity is
  `0.0` rather than `0.5`, a large gap IS certainty, and the contest is scaled
  rather than homogeneous. The counter to every trigger is the defender's own
  investment in the suppress half, point for point — the yin-yang property is
  exact cancellation rather than an asymptote.

## Consequences

- A realm/gear gap now buys trigger certainty when unmatched; that is accepted
  and is the point. Content authors accuracy and resist halves; `rate_scale` is
  the one retuning dial.
- The stock test kit (`accuracy 0.005` against a zero-evasion body) still lands;
  an exact `(0, 0)` pair is the design's miss, covered by a test.
- Tests: the ratio assertions in `test_combat_band_roll.gd` and
  `test_combat_stats_shape.gd` are rewritten to the flat shape; the registration
  scanner no longer classifies `crit_damage` as rate-shaped; `accuracy` is
  exempted from the "combat ids are not core ids" probe because core now DERIVES
  it by design.