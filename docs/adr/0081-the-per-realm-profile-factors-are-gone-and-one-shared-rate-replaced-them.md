# 0081 The per-realm profile factors are gone; one shared rate replaced them

- Status: Accepted
- Date: 2026-10-03
- Supersedes: the "Realm profile factors" section of ADR 0016 (P / C / F / T), and ADR 0013's
  "realm profile technique factor T = P^0.55" line
- Corrects: ADR 0028's "The seed is the only source of profile truth" line

## Context

Three ADRs publish a per-realm factor vocabulary that no longer exists anywhere.

ADR 0016 defined four factors read from **one shared power ladder**: `P` (reference budget),
`C = P^0.85` (capacity), `F = P^0.40` (throughput), `T = P^0.55` (technique), with
"`MindProvider` resolves it from `PowerLadder.value(index)`". ADR 0013 repeated the `T` line and
published concrete numbers: "for a base-45 actor, `mind_technique_power` runs 45.0 (R1) →
130984.16 (R30)". ADR 0028 said each body seed "carries `power_budget` (P), `capacity_factor` (C =
P^0.85), `throughput_factor` (F = P^0.40), `technique_factor` (T = P^0.55)" and that
"`BodyProvider` and `BodyTraining` load them".

**`PowerLadder` was deleted** by ADR 0050 (via ADR 0042): zero occurrences of `PowerLadder` or
`PowerScaleTuning` in `game/` or `tools/`. The only surviving mentions are two historical
comments — `core/realm_defaults.gd:63` and `core/realm_power_table.gd:10`.

**The four seed fields were deleted too.** `power_budget`, `capacity_factor`,
`throughput_factor` and `technique_factor` have **zero** occurrences across every `.tres` under
`game/data/` and every `.gd`. `BodyRealmSeed` (`modules/body_cultivation/realm_seed.gd:8-49`)
carries `integrity_maximum`, `integrity_target`, `insight_required`, `chance_base`, `chance_cap`,
`resonance_rank`, `channel_training` — and no P/C/F/T. The generators stopped emitting them on
purpose: `tools/cultivation/seed.py:278-279` — *"Deliberately NOT emitted ... Those four were a
second"*. `tools/cultivation/audit.py:108-109` and `report.py:81` say the same.

## Decision

**One shared rate replaced all four. `RealmRate.factor(realm_id)` is the only per-realm factor any
path reads.**

```gdscript
# core/realm_rate.gd
const RATE_STEP := 1.02
const NEUTRAL := 1.0
static func factor(realm_id: StringName) -> float   # RATE_STEP ^ ordinal
```

Six call sites, one per path per concern, across both training and provider:
`qi_cultivation/training.gd:44`, `qi_cultivation/provider.gd:54-55`,
`body_cultivation/training.gd:67`, `body_cultivation/provider.gd:63-64`,
`mind_cultivation/training.gd:60`, `mind_cultivation/provider.gd:63-64`.

- **ADR 0066's migration is what happened, and it held.** The three `*RealmProfile.gd` copies are
  gone, `test_realm_rate_parity.gd` is gone, and `tests/core/test_realm_rate.gd` carries the
  monotonicity pins forward.
- **`RATE_STEP ^ 29 ≈ 1.776`, not `P(29) ≈ 551.46`.** Every published figure derived from P/C/F/T
  is void, including ADR 0013's `45.0 -> 130984.16` and ADR 0013's "the sea runs 100 -> 825" — the
  sea half is still correct (`MindRealmSeed.sea_capacity`: `qi_refining.tres` 100.0,
  `primordial_origin.tres` 825.0), because capacity is an authored magnitude on the seed, not a
  factor product.
- **A local variable named `technique_factor` survives** at
  `modules/mind_cultivation/provider.gd:31`. It is fed by `_realm_factor(context)`, which returns
  `RealmRate.NEUTRAL` / `RealmRate.factor(...)` (`provider.gd:63-64`). The name is the only
  remaining P/C/F/T artefact and it no longer means `P^0.55`.

## Consequences

- **The rate/magnitude split (ADR 0050, ADR 0066) is the governing rule and is unchanged.** A
  magnitude is `RealmDef.power` from `core/realm_power_table.tres`. A rate is `RealmRate.factor`.
  Item magnitudes are `game/data/item_options/item_magnitude_scale.json`. Technique magnitudes are
  `core/technique_magnitude_table.gd` (`TECHNIQUE_STEP = 1.035714`, ~2.77x). Four per-realm tables,
  four different quantities, **none derived from a realm index**.
- **Never reintroduce a seed-carried factor.** ADR 0028's `power_budget` line was the second
  magnitude ladder ADR 0066 killed, and the seeds are clean because a tool refuses to write them.
- `tools cultivation validate` reads the authored magnitudes by realm id; nothing recomputes one.
  That is ADR 0060's "magnitudes are read, never recomputed" and it still holds.
