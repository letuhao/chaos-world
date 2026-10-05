# 0060 A verification tool must measure what its output claims

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0036 ("every cultivation path's gates are reachable"), ADR 0008
- Consistent with: ADR 0041, ADR 0050

## Context

Three tools printed a green result for a measurement they were not taking.

- `data audit` derived acquisition roots as `KNOWN_SOURCE_TYPES - {"craft"}`, so
  `boss:` and `domain:` were roots by construction. 872 items sourced only to a
  boss counted as obtainable, and `_unobtainable` could never fire. The premise
  behind that audit was also wrong: `ItemDef.sources`
  (`game/src/modules/items/item_def.gd:18`) is authoring metadata and **nothing
  in `game/src` reads it**, so the content graph cannot answer "can a player hold
  this" at all. The boss runtime does exist (`game/src/modules/loot/api.gd:64`
  `enter_domain`, `:91` `strike`, wired at
  `game/src/app/item_workbench_app.gd:226`) — the gap is that 326 of 331 boss
  records appear in no authored `LootEncounterDef`, and `gather`/`quest` have no
  route at all. 2880 of 8071 items are deliverable.
- `cultivation validate` compared gates to each other and never asked whether a
  gate could fail. `physique_required` is dead from R5 on: arrival physique is
  `rewards.physique + integrity_maximum * MILESTONE_PHYSIQUE_RATIO`
  (`game/src/modules/body_cultivation/progress.gd:13,36`), which exceeds the floor
  in 26 of 30 realms.
- `cultivation report` printed "failure rate stays at or above 12% even with
  perfect huyệt" while R26-R30 have `chance_base >= chance_cap`, so
  `BodyAdvancement._chance` clamps the acupoint term away and the band is
  zero-width. It also dropped any realm whose best case was certain
  (`if chance_range(seed)[1] < 1.0`) from the minimum it then quoted.

## Decision

- **"Obtainable" is two numbers.** `data audit` keeps the graph closure gating and
  reports runtime reachability beside it: graph 8071/8071, shipping 2880/8071.
  Each source type declares its route in `tools/data.py` (`RUNTIME_ROUTES`) as a
  script plus the symbols that must exist, and the tool verifies they do. A
  deleted runtime demotes that source type instead of silently keeping it a root.
- **Runtime availability is reported, not gated.** `data audit --fail-on-unreachable`
  is the gate; `tools check` does not pass it. The shortfall mixes a missing
  subsystem (no forager, no quest system) with missing authored content (no
  encounter hosting 326 bosses). Neither is a data defect inside a subsystem that
  ships, and a permanently red gate teaches everyone to ignore red.
- **A gate has two failure modes and both are asserted.** Reachability (ADR 0036)
  is joined by soundness: a gate must be able to fail (`body_physique_gate_dead`),
  a ratio gate must lie inside `(0, 1]` (`qi_gate_unsatisfiable`), and a premise
  the tool cannot read must fail loudly (`gate_soundness_premise_unreadable`)
  rather than default to a permissive value.
- **Magnitudes are read, never recomputed.** Every check resolves realm strength
  and item scale from `core/realm_power_table.tres` and the authored item scale by
  realm id (ADR 0050). No check computes a magnitude from a realm index.

## Consequences

- `tools check` is **red** on `cultivation validate`: 26 dead physique floors
  (R5-R30) and 5 degenerate chance bands (R26-R30). Both are data defects in a
  subsystem that ships; the body-cultivation slice owns the fix.
- Rejected: gating runtime availability now. It would be red until a forager, a
  quest system and 326 encounters exist, and `ok data audit clean` must not be the
  price of admitting that.
- Rejected: deriving source reachability from `ItemDef.sources` at runtime. It is
  metadata; making it authoritative would put acquisition policy in the items
  module behind a 12-method facade (ADR 0050's reasoning applies unchanged).
- Deferred: the same soundness assertions for the mind path's gates
  (`clarity_required`, `purity_required`) and for `insight_required`, which no
  assertion bounds because `meditate` has no per-realm ceiling.
- ADR 0036 stays in force for reachability; ADR 0041 (a decided tribulation) and
  ADR 0050 (authored magnitudes keyed by id) are unchanged and not superseded.