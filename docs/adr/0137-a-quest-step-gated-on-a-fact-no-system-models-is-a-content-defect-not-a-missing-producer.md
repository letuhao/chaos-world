# A quest step gated on a fact no system models is a CONTENT defect, not a missing producer

Completes the ADR 0114 chain's demand side. Does not touch the power ladder or any
per-realm table.

## Status

Accepted.

## Context

`tools gate_reach check` reports 10 `unbacked_demand`: quest steps gated on facts no
authored beat produces. Measured 2026-10-03, and the ten are **not one problem**.

Five are *player actions in systems that exist but were never wired*:

| fact | real owner | the seam |
|---|---|---|
| `sect_post_held` | `sect` | `SectApi.promote` writes `position`; nothing records that an office was HELD |
| `oaths_discharged` | `sect` | `InstitutionClaim.owe`/`.settle` have zero production callers, so `settled()` is permanently false |
| `household_heir_registered` | `clan` | `ranks` publishes `heir`; no verb writes it |
| `duels_won` | `combat` | `CombatDuel` counts DEFEATS only; a win has no ledger |
| `third_man_spared` | `combat` | no surrender/spare outcome exists at all |

Five name **systems this program does not have**: `mountain_circled_once` (no travel or
map traversal — ADR 0001 chose 2D and never built one), `bound_name_called` (no naming
system), `the_road_severed` (no road system), `emberblood_furnace_lit`
(`ResourceNodeDef.kind` is CONTENT that never branches a formula, so a furnace has no
lit/unlit state), `vigil_broken` (no vigil). Verified by module census: there is no
travel, naming, road, or watch module under `game/src/modules`.

A trap sits in the middle of this. Eight of the ten **appear in `src/`**, in
`modules/destiny/destiny_projection.gd:94-104`, each mapped to a destiny **counter**. That
reads as a producer and is not one: `destiny_projection.gd:152` is the only caller of
`DestinyApi.record`, and it is called from tests alone. The counters are equally dead —
DEF-0168's shape in a second ledger.

## Decision

**Split by cause, and refuse the one repair that would make the gate green.**

For the five with a real owner, the owning module records the fact when the action
succeeds. One ledger (`world_facts`), one writer set, no new subsystem.

For the five with no system, the **quest content** is the defect. Re-authoring or
removing those steps is a content decision, and it is made deliberately rather than by
a producer being invented to match a demand.

The refusal that matters: **do not** add these ids to an ambient world roster. A world
pulse that reports *you* spared the third man, broke the vigil, won three duels and
registered as an heir is not a simulation — it is the gate's demand echoed back. It would
also falsify
`test_a_fact_the_world_never_reports_is_still_outstanding`, which asserts a player's
duels are **not** ambient. A gate cleared by a producer that mirrors the gate is the ADR
0066 quiet lie, produced by code rather than by prose.

## Consequences

- **`gate_reach` staying red is the correct state** for the five with no system, until
  the content changes. It is a finding, not a failure to route around.
- **`oaths_discharged` is the first of the five to fix**: obligation lines already open at
  `sect` join and `SectGate` already reads `duty_owed`. Only the discharge is missing, so
  it is a half-built seam rather than a new feature.
- **`InstitutionClaim` debt that accrues and never discharges is a live balance bug**
  independent of quests — `settled()` is permanently false for every member.
- **The facade cap is a real constraint on the fix.** `SectApi` is at the 12-method cap
  (`rules.MAX_FACADE_PUBLIC_METHODS`, pinned by `test_sect_no_power.gd`), so a discharge
  verb is a 13th method and needs an explicit call, not a quiet addition.