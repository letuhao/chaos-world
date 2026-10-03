# 0110 Tier 2 statuses are authored content and ship behind the status element gate

- Status: Proposed
- Date: 2026-10-03
- Amends: ADR 0090 (the tier-1-only clause)

## Context

ADR 0090 made the status catalogue authored `.tres` data and shipped ten of the twenty
statuses. Its reason for the ten was measured, not stylistic: `ElementDefaults.advanced()`
has empty `generates` on every entry, so every tier-2 matchup row is strictly dominant —
row mean `1.04` against tier-1's `0.950` (`default_elements.gd:28-35`, ADR 0069). Shipping
a status on a dominant element is balancing content on a broken table.

Two things have changed since. The tier-1 table is now **confirmed correct as authored** —
`fire > metal` reading 1.5 with `fire > wood` at 1.0 is the 相克 cycle, and DEF-0140's
transposition claim was filed against the test, not the table, and retracted. And the
catalogue is a content tree with a **closed ten-name mechanic vocabulary**
(`status_def.gd:89-100`), so the twenty statuses can never be twenty distinct mechanics:
ten shapes exist because ten were authored. A vocabulary that cannot grow without a
`status_def.gd` change is a real constraint on how many statuses can be written, and it is
the constraint that decides this.

## Decision

**The ten tier-2 statuses are AUTHORED now, and the loader still refuses them.** The gate
stands; only the authoring happens ahead of it.

- Two per advanced element, each pair mechanically distinct — one channel that spends a
  pool (`health_share` / `element_power`) beside one control, stat-modifier or amplifier.
- **Every advanced element reuses a mechanic tier-1 already resolves**, so nothing in
  `api.gd` / `status_runtime.gd` needs a tier-2 branch. `_pulse` keys off
  `magnitude_unit` and `_sibling_burns` off `mechanic()`, neither of which names an element.
- **Every tier-2 element claims exactly one `on_landed_blow` status**, and it is the
  COMBAT-scope member of its pair. That is `StatusCatalog._landed_blow_collisions`
  (`status_catalog.gd:112`) satisfied in advance, so lifting the gate cannot produce an
  ambiguous element.
- **`light_expose` and `dark_erasure` stay refused, now as names.** ADR 0090 refused them
  on their own reasoning (no victim-side stat to amplify; rewrites ten resistance ids).
  Nothing in this change creates a victim-side amplification stat or inverts a resistance,
  so the reasoning stands and the catalogue is free to name something else instead.
- **The gate is one line: `status_def.gd:172-181`.** It fires before the mapping is
  consulted, so `status_for_element` correctly answers `&""` for every advanced element
  and nothing needs to know tier-2 exists.

## Consequences

- The catalogue is twenty authored defs on disk and **ten published**. `rejected()`
  reports each tier-2 def by name and reason, which is what keeps ADR 0090's withholding a
  *rule* rather than a convention — a designer who authors one finds out which file to
  delete. The tests assert both halves: the ten files validate against every OTHER rule,
  and the gate is the only thing holding them.
- **Lifting the gate is then a one-line edit plus a test edit, not an authoring project** —
  which is the whole reason to author ahead of it. The minimal change is to delete the
  `elif not TIER_ONE_ELEMENTS.has(element)` branch at `status_def.gd:172`, and to widen
  `TIER_ONE_ELEMENTS` to `ElementStats.BASE_ELEMENTS + ADVANCED_ELEMENTS` (or rename it).
  Everything downstream — `status_for_element`, the collision report, the facade — already
  behaves correctly for twenty defs.
- **`status_catalog.gd` needs no change for twenty defs.** Its walk is over sorted ids and
  `status_for_element` reads `on_landed_blow`; the collision rule is already correct for a
  tree of any size. The one assertion to revisit is the five-claimant count in
  `tests/modules/combat/test_combat_exchange_status.gd:328`, which becomes ten.
- The numbers in the ten new files are **guesses until a balance pass**, on the same terms
  ADR 0090 states for tier-1: every tunable lives in the `.tres` or in `CombatTuning`, and
  no tier-2 status pins a magnitude as a literal in logic.
- The cost is admitted: the ten statuses are dead content until ADR 0069's
  `TIER_MASTERY_STEP` divisor lands in `ElementProvider`. Authoring them costs a directory
  of unread defs and buys an authored, reviewed, test-covered catalogue the day the table
  is fixed — which is strictly better than authoring twenty guessed statuses on the day
  the fix lands.