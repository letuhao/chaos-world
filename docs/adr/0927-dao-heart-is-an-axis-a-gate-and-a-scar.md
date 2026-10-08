# 0927 dao heart is an axis, a gate and a scar

- Status: Accepted
- Date: 2026-10-08
- Closes: BL-0932
- Depends on: ADR 0020 / 0061 (the tribulation), ADR 0031 (the recovery elixir), ADR 0050 (keyed tables)

## Context

`Stat.DAO_HEART` was derived (`will`), displayed by the presenter, and granted by gear,
sets, bloodlines and fates — and read by **no mechanic** (BL-0932). Two docblocks named
it while the code spent something else: `WAVE_TOLL` said
"in dao heart" and `_charge_toll` said "dao-heart strain", and both spent COMPREHENSION;
`TribulationEndurance._dao_heart` returned comprehension under the stat's name. The
`HEART_DEMON` tribulation type existed in the pressure table and was never constructed.

The owner ruled both axes plus a crack (2026-10-08).

## Decision

**The dao heart is an axis, a gate, and a scar — and every one of them is live.**

- **An axis.** `TribulationEndurance` reads TWO separate terms:
  `MIN + comprehension * 0.01 + dao_heart * 0.01 - rating * PER`, comprehension at its
  BASE (a fight erodes it) and the dao heart at its DERIVED value (where grants land).
  The helper named `_dao_heart` returned comprehension; it is split into `_comprehension`
  and `_dao_heart` and the misnomer is gone.
- **A gate.** The deepest trials ask for it: `Breakthrough.DAO_HEART_BY_TIER` (keyed by
  TIER, the key `WAVES_BY_TIER` uses, never by ladder position) asks 24 at the
  Transcendent tier — the 9-wave fights at the top of the ladder — and nothing below it,
  and `dao_heart_ok` joins `tier_gates_met`, the one shared tier gate every path's
  condition delegates to. The qi preview names the refusal (`dao_heart_too_low`), so it
  is observable rather than a silent no.
- **A scar.** It CRACKS on a failed breakthrough (`HEART_CRACK_ON_DEVIATION := 2.0`,
  charged by `QiBreakthroughTransaction._deviate`) and on every wave of a HEART-DEMON
  trial (`Tribulation._charge_toll` spends the heart for that type; every other type
  keeps spending comprehension, as the body path's own comment documents). The scar is a
  NEGATIVE base offset on the dao heart's own id, added by the derivation — NOT a
  `StatModifier`, which `ActorStats.to_dict` does not serialize: a modifier would heal
  itself on the next load and the crack would be a lie. `DaoHeart.crack` floors it so
  strain cannot leave a negative heart, and `_put` floors the effective value too.
- **And a rebuild.** `QiTraining.recover` mends the crack with the realm's recovery
  elixir — the same elixir that closes a dantian scar and repairs a burned channel — and
  a crack alone is enough to justify the spend (all-or-nothing counts it). Authored
  `core_dao_heart` grants compose on top of a crack, so content is a second way up.

## Consequences

- **Every authored grant is live**: gear options, sets, bloodlines and fates. Equipment
  is the path that APPLIES — a consumable's stat targets are reported and never applied
  (`ItemUse`, ADR 0001) — so reachability is proven the real way: `test_dao_heart.gd`
  stands a body at R26, equips the two authored uniques the realm-tier guard admits
  there (`unique_void_coil_coiled_heart` +20, `unique_ironhide_hearthguard` +6, against
  the ask of 24), and watches the gate open through the real preview.
- **Both axes move the same fight from different sources**, and neither is the other
  under a new name: the two-terms test moves each by 30 points and asserts the term.
- **The crack is a pair, not a punishment**: loss (a failed breakthrough, a heart-demon
  wave) and rebuild (the recovery elixir, or gear) are both shipped, so the deepest
  gates stay reachable through play. Nothing here can strand a hero.
- **The `HEART_DEMON` type finally means something** beyond its 1.2 pressure: it is the
  one trial that spends the stat it is named for.
