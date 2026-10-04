# 0182 Items are a cultivation system, so every item magnitude reads the ladder keyed by realm id

- Status: Proposed
- Date: 2026-10-04
- Amends: AGENTS.md 139-146 (the magnitude/rate split), which already lists the item table
- Depends on: ADR 0050 (magnitudes are authored data keyed by id), 0055 (the technique ladder),
  0116 (one rate), 0157 / 0166 (a drop pays its item's own rung)

## Context

**Owner ruling, 2026-10-04:** *"the item follow ladder too, it have 30 realms, if the current
context violate it ... the items consider as a cultivation system so it follow ladder rule."*

AGENTS.md 146 already lists `item_magnitude_scale.json` as a deliberate third table. What it
does not say is **which numbers the table binds**, and that is what an agent gets wrong: an
item magnitude and an actor stat look identical at the call site and are governed differently.

Measured (`cultivation loot-magnitude report --scope all`, plus the walks named in Guard):

- `item_magnitude_scale.json` — **30** realms, its keys exactly the **30** `RealmDefaults`
  ladder ids (**0** missing, **0** extra), linear **1.0 -> 3.9x, +0.1 per rung**, keyed by id.
- Three tables, never derived from one another: items **1.0 -> 3.9x**; techniques
  **1.0 -> 2.7667x** (`technique_power report`; `TECHNIQUE_STEP` 1.035714,
  `technique_scales.gd:18`); actors **1.0 -> 551.46x** (`realm_power check`, exit 0).
- **6307** of **8084** reachable direct entries paid a rung that was not their item's own
  before ADR 0166. Dropping the band's substitution re-prices every one: **4740** gain
  (x1.03 min, **x2.09** median, x3.90 max), **1567** lose (x0.26 min, **x0.73** median,
  x0.97 max), **0** neutral. Up to 3.9x on **78%** of the reachable catalogue — the ruling's
  direct consequence, not a side effect.

## Decision

**The test: ask what owns the number's meaning — not whether it was computed.**

- **An item magnitude is ladder-governed, so it is read and never derived.** Its realm axis is
  authored data keyed by realm id: `OptionCatalog.realm_magnitude_scale`
  (`option_catalog.gd:246`). Deriving one from a realm **ordinal**, a **literal**, **another
  scale**, or an **actor's stats** is a violation. `option_catalog.gd:218-232` is the reference
  form of this asymmetry — magnitude by id, rate by ordinal — and needs no change.
- **A magnitude is classified by its owning table, never by its shape.** An **item** magnitude
  reads the item ladder above. A **technique** magnitude reads `TechniqueScales.magnitude_at`
  (`technique_scales.gd:52`), which ADR 0055 makes the one magnitude that *is* a closed form
  over the ordinal — `pow(TECHNIQUE_STEP, index)`, bounded by the same work budget as
  `RATE_STEP`. Neither may read the other, and no third site may re-derive either. This ADR
  does not change that asymmetry; it is exactly why the rule has to name the owner, because
  "is it a formula?" does not separate the two.
- **An actor stat baseline is owned by the actor and is compliant** (AGENTS.md 142: *"each
  path's own magnitude is authored on its own seed ... applied once"*). So the violation is
  **computing a magnitude in the wrong place**, not computing it: a stat derived from the
  actor's own stats is that actor's; the same number arrived at by reading the item ladder
  from inside an actor path is not.
- **A rate may gate a magnitude; a rate may never become one, nor be derived from one.**
  `RealmRate` (`realm_rate.gd:76`, `RATE_STEP` 1.02) stays a rate — bounded, under 2x across
  the whole ladder by construction (`realm_rate.gd:74-75`), never a magnitude table.
- **An ambiguous site is classified, not escalated.** One question decides it: *does this
  number exist without an actor?* Yes -> a magnitude, bound to its owning table. No -> an
  actor stat or a rate.

**Pending audit — no verdict asserted here.** `spine.gd:199`
(`base *= RealmRate.factor(attacker.realm())`, over `base := technique.magnitude` at `:197`)
and `combat_boot.gd:88` (*"the spine's S1 is `technique.magnitude x RealmRate.factor(realm)`"*)
apply a bounded rate **to** a magnitude. A separate audit owns whether that is legitimate;
both sites are already classified by the rule above, so only the verdict is outstanding. If
the audit disagrees, this ADR stands and the verdicts change.

## Evidence

All **30** `mind_sea_catalyst` items (`progression_roles.json`) now pay their own rung exactly
— **30 of 30, no drift** — and the same report finds **0** items whose authored realm has no
scale row. Each item's authored realm is the realm named in its own id:

| item | authored realm | ladder ordinal | pays |
|---|---|---|---|
| `mind_qi_refining_sea_catalyst` | `qi_refining` | 0 | 1.00x |
| `mind_core_formation_sea_catalyst` | `core_formation` | 2 | 1.20x |
| `mind_spirit_sea_sea_catalyst` | `spirit_sea` | 10 | 2.00x |
| `mind_transcendent_sea_catalyst` | `transcendent` | 27 | 3.70x |
| `mind_primordial_origin_sea_catalyst` | `primordial_origin` | 29 | 3.90x |

`mind_core_formation_sea_catalyst` is the sharp case. It paid `transcendent` **3.70x** before
ADR 0166 — **25** ladder positions above the rung it is authored at — and pays its own
**1.20x** now. Reproduce the full 30 by walking role -> `data/items/**/*.tres` `realm =` ->
the scale row.

## Guard

Live today; every one predates this ADR.

- `tests/modules/items/test_option_parity.gd` recomposes each window from the **authored**
  `scales` column, looked up by name, and compares it against `OptionCatalog` — so a runtime
  that stops reading the ladder fails.
- `tests/app/test_mutation_guards.gd:494-516` fails if any ladder realm has no usable row.
- `tests/modules/combat/test_combat_damage.gd:184-198` keeps `combat/damage.gd` realm-blind.
- `uv run python -m tools realm_power check` (in `tools check`) holds the actor table's shape.

**Not built.** Nothing rejects an item magnitude computed locally. `tools/arch/rules.py`
matches `magnitude` **zero** times and `test_combat_damage.gd`'s realm-blindness scan is
scoped to a single file, so a new site could read a ladder, an ordinal or a literal and stay
green under every check. The structural pin ADR 0116 and ADR 0169 already argue for — a
source-reading test failing on any `src/` declaration of an item magnitude outside
`OptionCatalog` — is owed, and is **not** claimed here.

## Consequences

- The band no longer prices magnitude, so a drop's context realm cannot reach an item's power;
  retuning the ladder moves every item at that rung together.
- This ADR adds no table and retunes none: `RATE_STEP`, the ladder values and the actor table
  are untouched. Reconciling the item table with the actor table remains ADR 0050's open
  question and needs its own ADR.