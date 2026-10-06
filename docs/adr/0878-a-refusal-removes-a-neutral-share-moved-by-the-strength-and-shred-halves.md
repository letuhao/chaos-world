# 0878 a refusal removes a neutral share moved by the strength and shred halves

- Status: Accepted
- Date: 2026-10-06

## Context

- `parry.strength`/`parry.shred` and `block.strength`/`block.shred` shipped declared,
  defaulted to `0.0`, and read by nothing: a parry always kept exactly `PARRY_COST`
  (`0.5`) and a block `BLOCK_COST` (`0.75`) whatever either side invested.
  `combat_boot.gd` and the spine call these four the "wave E" leftovers.
- ADR 0877 established the flat-delta shape for every pair: one exchange rate
  (`rate_scale`), parity cancels, neither input is capped, only the output is bounded.

## Decision

- A landed response REMOVES a share of the blow:
  `removed = clampf(neutral + (strength - shred) / rate_scale, 0.0, refusal_cap)`,
  and the defender pays `1.0 - removed`.
- The NEUTRALS are the shipped costs: a parry keeps `PARRY_COST` (`removal 0.5`) and a
  block keeps `BLOCK_COST` (`removal 0.25`), so an unauthored pair is byte-identical to
  what shipped.
- The removal is CAPED by a new `CombatTuning.refusal_cap` (shipped `0.95`, Keepverse's
  own per-response cap): no stack of `strength` refuses a landed blow outright, and the
  floor is `0.0` — a fully shredded response removes nothing, as in Keepverse.
- The pair is read at S2's aftermath (`CombatSpine._refusal`), never inside the band
  roll, which must stay one comparison. The ownership rule ADR 0068 wrote is unchanged:
  `break` is the attacker's TRIGGER half and `shred` is the attacker's AFTERMATH half;
  `rate` is the defender's trigger half and `strength` the aftermath half.

## Consequences

- `refusal_cap = 0.0` on a bare `CombatTuning` makes every response remove nothing —
  visibly broken, the convention every field on that resource keeps.
- Content may now author the four halves; before this change, authoring them did
  nothing. This is the last declared-but-unread pair in the combat vocabulary.
- Tests: `tests/modules/combat_engine/test_combat_refusal_pair.gd` pins the neutral, both
  directions, parity, and the cap. The band-roll suites are untouched because the band
  never reads the pair.