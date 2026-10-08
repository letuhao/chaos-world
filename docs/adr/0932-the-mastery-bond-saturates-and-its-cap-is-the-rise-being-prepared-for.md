# 0932 the mastery bond saturates and its cap is the rise being prepared for

- Status: Accepted
- Date: 2026-10-08
- Closes: BL-0938
- Depends on: ADR 0004 (the elemental path), ADR 0116/0268 (the shared rate), ADR 0200 (the mitigation ratio), ADR 0924 (the affinity door's caps)

## Context

The audit measured the elemental mastery channel as a free, unbounded faucet: `practise`
cost nothing and never refused, the provider multiplied mastery LINEARLY
(`affinity * (1 + 0.1 * mastery)`), and qi's elemental term spends that power directly —
so ~61 free sittings read `element_power_<e>` ~271x, past the whole 30-realm ladder
(`RealmDef.power` tops at 551x) and priced in nothing. The elixirs (100/240/600) were
strictly dominated by free sittings that ride the realm rate. Only three seeds author
`element_mastery_required` (spirit_condensation 900, earth_immortal 1800, transcendent
2700), and they were the only things mastery answered to.

The owner's ruling: BOUND it — saturate the output, cap the input per element — and size
the advantage HIGH (x4 at full), so elemental resistance and weakness exploitation are
the pivot rather than a memory. The yin-yang condition rides along: the x4 is only sound
if the defence side can answer it, and the measurement of that answer is part of this
decision.

## Decision

- **One saturating curve, shared by power and crit** (`ElementMastery.saturation`):
  `s(m) = m / (m + 300)`. Zero at zero, exactly half at 300, strictly rising and strictly
  below 1.0 — every further point still pays, worth less each time.
- **The power ceiling is x4** (`ElementProvider.POWER_CEILING = 3.0`):
  `element_power = affinity * (1 + 3.0 * s(mastery) / tier_divisor)`. The existing
  per-tier divisor (ADR 0069) now taxes the CEILING instead of the linear rate; tier 1
  still pays it in full. The omni channel reads the summed mastery on the same curve.
- **The crit mastery term is paired, not proportional** (`CRIT_MASTERY_CEILING = 0.6`):
  the old `mastery * 0.002` reached +6.0 at the cap — an unanswerable second ladder. The
  only lever a non-elemental defender can move is `will` (topping near 0.165), so the
  ceiling is set to a comparable span.
- **The cap is per element and keyed to the tier the body is PREPARING FOR**: mid-tier
  realms read their own tier, and the last rung of a tier reads the tier above — 600 /
  1200 / 2000 / 3000 at Mortal / Spirit / Immortal / Transcendent. That read is what
  keeps each authored rise gate (900/1800/2700) reachable on ONE element while a body
  still stands below it, and it is keyed by tier so an inserted realm cannot shift a cap.
- **The training verbs enforce it, by name**: `practise` and `use_elixir` return named
  refusal dictionaries (`mastery_capped`), a sitting/drink that would cross the cap lands
  ON it and reports what it applied, and at the cap nothing is consumed. The facade's
  `practise` is a Dictionary now; every call site was updated.

## Consequences

- **The advantage is bounded and reachable**: at the transcendent cap (3000) the power
  multiplier is `1 + 3 * 0.909` = 3.73x, approaching x4 and never crossing it. At the
  mortal cap (600) it is 3.0x. `test_element_mastery_bound.gd` pins the curve, the caps,
  the gate reachability against the AUTHORED seeds, and the refusals.
- **The defence answers, by measurement**: `test_element_mastery_answer.gd` measures a
  full-mastery fire attack against a prepared defender (weak-against nature, root at the
  attunement cap, top-of-ladder will, the authored ward) — the prepared defender takes
  ≤0.55x of a full-mastery blow, the mitigation contest moves off zero, no reading reaches
  the ceiling, and the relationship is realm-invariant at a fixed mastery.
- **A deliberate difficulty shift**: an unprepared attempt at a tier rise now gets a cap
  of 600/1200/2000 instead of unbounded mastery — training pressure is real at every
  band. The cap-aware qi traversal still closes all three gates (`qi_gate_probe`).
- **The old linearity is gone everywhere it was read**: `CRIT_MASTERY_STEP` is deleted,
  `TIER_MASTERY_STEP` survives as the divisor on the new ceiling, and the pre-bond
  `test_mastery_scales_power` figure (15.0) moves to the saturated one.
