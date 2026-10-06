# 0876 penetration is answered by absorption and every contest half is read

- Status: Accepted
- Date: 2026-10-06

## Context

- Keepverse resolves every contest as a flat difference of flat-composed
  magnitudes (`penDelta = pen - absorption`, `Contest = Sigmoid(flat delta)`),
  and every offense id has a defense twin that something reads.
- Our tree declared the twins but left three unread: `absorption` (nothing
  read it), `reflect.resist.damage` (nothing read it), and the parry/block
  break/shred/strength halves (wave E, documented deferral).
- `reflect.resist.damage` shipped a `1.0` baseline while being consumed as a
  share subtracted from `1.0` — the same dead channel `crit_resist_damage`
  shipped with in ADR 0875.

## Decision

- Penetration is answered: `CombatStats.pierce(pen, abs) = maxf(0, pen - abs)`.
  The three damage mechanisms and `StatusApply.elemental_resist` read through
  it. Either half floors at zero on its own side; unauthored absorption reads
  `0.0`, so every existing number is byte-identical until content authors it.
- The bounce carries its resist: `recoil.bounce` multiplies by
  `(1 - reflect_resist_damage)` floored at zero, the S6 crit shape. The resist
  baseline is `0.0` (was `1.0`, which zeroed every bounce).
- Parry/block break/shred/strength stay deferred to wave E, and the hit/crit
  ratio contests stay as ADR 0215 wrote them. This ADR wires unread halves; it
  does not re-decide live contests — those are follow-up slices with their own
  numbers, not drive-bys in a wiring change.

## Consequences

- `test_combat_stats_shape` still pins the rate/default tables; the resist
  baseline move is the only membership-adjacent change, and it follows the
  `crit_resist_damage` precedent out of every rate list.
- A new absorption/resist authoring immediately contests; before this change
  it silently did nothing.
