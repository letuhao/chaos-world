# 0090 The status catalogue is authored data and tier-1 ships first

- Status: Proposed
- Date: 2026-10-03

## Context

ADR 0004 says elements are authored as `.tres` `ElementDef`s, and in fact **all ten are
built in code**: `ElementDefaults._make` constructs every one
(`modules/elements/default_elements.gd:34-43`) and ADR 0004's own consequence permits
*"appending to `ElementDefaults`"*. The same tension now applies to statuses.

`AGENTS.md` caps the value of a balance surface at "the balance surface is data": a
number a designer cannot edit without a programmer is not a balance surface. But the
twenty statuses the designs enumerate are **not twenty authored defs waiting to be
filled in** — they are a design agent's invented catalogue, several of whose constants
the designs themselves mark as reasoned guesses. Authoring twenty guessed `.tres` files
would put twenty guesses into the content tree where a later agent would read them as
settled balance, and `tools data audit` would guard their shape without ever checking
their numbers.

ADR 0069's measured defect: every entry in `ElementDefaults.advanced()` has empty
`generates`, `lightning`/`ice`/`wind` carry two `overcomes` and `light`/`dark` one
(`default_elements.gd:20-24`), giving tier-2 row means of 1.100 against every tier-1
row at 0.875–0.975. **Tier-2 elements are strictly dominant on the shipped table**, so
a status balanced on `lightning` or `ice` is balanced on a broken table.

## Decision

**`StatusDef` is a module-owned `Resource` authored as `.tres`, and the catalogue ships
TIER-1 ONLY.**

- `StatusDef` lives in the module that owns the statuses, never in `contracts/` — ADR
  0056's rule, and `rules.py:125-132` warns on a `Resource` there. ADR 0004's `ElementDef`
  in `modules/elements/` is the precedent.
- `StatusDef` carries exactly the instance fields of ADR 0086 that are **authored**:
  `id`, `element`, `kind`, `scope`, `stacking`, `duration`, `magnitude_unit`,
  `magnitude_cap`, `tick_interval`, `mitigation_tags`, `payload`. Computed magnitudes
  (`STATUS_POTENCY_SCALE` and friends) are **not** per-status fields; they are
  `CombatTuning` fields on `combat_damage.tres`, so a rebalance is one `.tres` edit and
  no test re-pins a literal.
- **Ten statuses ship: two per tier-1 element (metal, wood, water, fire, earth).**
  `ElementStats.BASE_ELEMENTS` (`modules/elements/stats.gd:20`) is the list. The ten
  tier-2 statuses are **withheld, not deferred-and-forgotten**: they land after ADR
  0069's `TIER_MASTERY_STEP` divisor is implemented, because shipping a status on a
  dominant element is balancing on a defect.
- `mitigation_tags` empty is an authoring error `tools data audit` rejects, the same
  rule ADR 0075 already states for a hazard zone.
- **The stat op is validated against the stat id, not the status.** `tools/data.py`
  resolves `RATE_STATS` by regex over `contracts/stat.gd` (`tools/data.py:1198-1212`),
  so the audit checks `Stat.DAMAGE_REDUCTION` (baseline `0.0`,
  `core/actor_stats.gd:172`) for FLAT and a rate id for PERCENT — the ADR 0022 rule,
  applied at the one place that already knows which ids are rates.
- The designs' catalogue is **not** adopted wholesale. Two statuses are refused now, on
  their own stated reasoning: `light_expose`, whose only described effect is an S7
  amplification term that is not a victim-side stat any code owns, and
  `dark_erasure`, which rewrites ten resistance ids and inverts the property ADR 0069's
  resistance formula is built on. Both are design questions, not authored content.

## Consequences

- Twenty statuses become **ten**, and the ten that ship sit on the element set whose
  matchup table ADR 0069 measured as balanced (tier-1 row mean exactly `0.950000`).
  The catalogue grows to twenty when the tier-2 fix lands, as a content edit.
- Adding a status is a `.tres`, so ADR 0004's "adding an element is data, not code"
  extends to statuses without a second convention.
- The cost is admitted: tier-2 elements have no statuses until the divisor ships, so
  `ice`/`lightning` builds are weaker. That is deliberate — an even-but-weak option
  beats a strong option on a broken table.
- Every number in the twenty-status catalogue that both designs flagged as a guess stays
  a guess until a balance pass against real content, and lives in `CombatTuning` where
  the pass can move it.
- The catalogue is `.tres` **content**, not a Markdown table, so it does not violate the
  allowed-docs rule; the two design docs under `docs/design/status-system/` remain
  outside policy and are tracked in DEF-0114 for an owner ruling.
