# 0204 A copied manual carries a band around an authored value and never a different value

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0055 (bounded ladders), ADR 0053 (three states), ADR 0054 (passive delivery), ADR 0056 (module-owned Resource), ADR 0160 (learn cost; passive mastery), ADR 0070 (no unconsumed share)
- Relates to: DEF-0246, DEF-0100

## Context

The humans asked for technique manuals to roll their own numbers, the way skills
do in the setting they are drawing on: an inscribed manual whose **text** is fixed
and whose **transmission** is not. The mechanic is not decoration — a copy that
has passed through many hands carries corrections a reader can act on.

Four constraints made the obvious implementation wrong, and each was measured
rather than assumed.

- **ADR 0055's ladders are guard-enforced.** `tools/technique_power check` walks
  the 29 consecutive ratios of `technique_magnitude_table.tres` and fails above
  `TECHNIQUE_STEP = 1.035714`. Any roll that moved `magnitude` would either fail
  that gate or, worse, be applied after it and be invisible to it.
- **`magnitude` is not per-actor.** `CombatSpine.base_damage` reads
  `def.magnitude` off the **shared catalog resource**, and `app/` and other
  modules call the spine directly for hits that never pass through `techniques`.
  A band that existed only on the technique route would be on for one hit and off
  for the same actor's next one.
- **Mastery already multiplies some of these.** ADR 0055 publishes `qi_cost` at
  `0.94^n` and `cooldown` at `0.96^n`, and ADR 0160 scales a passive's stat values
  by `1.15^rung`. A band on the same value is a **second** multiplier — the exact
  double-count ADR 0160 refuses by name for the capacity channel, and the defect
  this program has already produced once.
- **Options are bounded.** `master_option_pool.jsonl` gives every option
  `bounds.min`/`bounds.max` and `OptionCatalog.clamp_to_bounds` enforces the
  window at authoring time. A roll outside it is a balance defect, not variance.

## Decision

`TechniqueMarginalia.draw(def, rng)` returns a **band**: for each authored option
value, an offset drawn inside that option's own `bounds`. It never returns a
different option, never returns a different authored value, and it is refused for
the four numbers it must not touch.

**Why these values and not the others** — the refusals are the decision:

- **`magnitude`** is refused: it is ADR 0055's ladder coefficient, it is read off
  a shared resource, and a band would multiply a base already scaled by the realm
  rate.
- **`qi_cost`, `cooldown`, `stamina_cost`** are refused: the first two are exactly
  what the mastery ladder discounts, and a discount column applied to a band is a
  number that reads as a benefit and pays twice.
- **Option values** are the only thing that varies.

**Pool capacity stays refused**, by the same rule and for the same reason as ADR
0160: `RealmScaling` already MULTs `MAX_QI` and `MAX_STAMINA` by the realm's own
power, and a band on a capacity is a fourth multiplier on a number that has three.
`TechniqueMarginalia.is_capacity_effect` is the shared predicate, and
`CodexEntry` calls it rather than restating the test.

**The roll is drawn once and is a property of the copy the actor holds.** It is
stored in the codex row's `realized` payload, drawn only for a row that carries
none, and re-read on every subsequent access. A second copy of the same manual may
roll differently; the same copy never does. This is why the draw is guarded by
`realized.is_empty()` — an unguarded redraw is a roll that moves under the player.

**The facade does not grow.** `TechniquesApi` is at `MAX_FACADE_PUBLIC_METHODS`
(12) and publishes 12. `TechniqueMarginalia` is reached the way `TechniqueCasting`,
`TechniqueDelivery` and `TechniqueCastView` are: a named type in this module,
referenced where it is needed and published as a constant rather than as a
thirteenth method.

## Consequences

- **A learned technique's numbers vary per copy, and never move afterwards.** The
  codex screen publishes the stored band, so what a player reads is what they will
  get.
- **The authored ladders are untouched.** `technique_power check` still passes and
  still means something, because nothing in this path writes a ladder.
- **Rarity still decides the band, and nothing else does.** `ItemRarity` decides
  how wide a roll may be; it does not decide the roll, and
  `ItemRarity.magnitude_budget` remains dead code (DEF-0273) rather than becoming
  a fourth magnitude table by accident.
- **A future option that should not vary must be named.** The refusal is a
  predicate, so a new channel is one branch in
  `TechniqueMarginalia.is_capacity_effect`-style code rather than a silent
  default.
- **Determinism is the test's job.** The suite seeds the RNG explicitly; nothing
  in production calls `randomize()`.
