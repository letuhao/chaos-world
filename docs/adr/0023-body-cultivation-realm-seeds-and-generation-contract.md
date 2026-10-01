# 0023 Body cultivation realm seeds and generation contract

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0015 gave body cultivation acupoints, but only two storage tiers (Minor, Major) and no
per-realm content. A body cultivator had nothing to *do*: no breakthrough pill, no channel
training, no reward, and no rule for what a given realm demanded. Immortal+ acupoints were
reserved but unreachable. The progression had to become seeded, auditable content rather than
hardcoded numbers.

## Decision

- **Realm seed** (`BodyRealmSeed`, `.tres` per realm at `data/body_cultivation/realms/`) declares
  one destination realm's whole contract: `breakthrough_item`, `strengthening_item`,
  `progress_required`, `physique_required`, `quality_required`, `quality_target`,
  `required_meridians`, `required_refinement`, `refinement_cap`, `integrity_maximum`, `rewards`.
  A seed describes the realm being *entered*, so preparation never depends on channels that only
  unlock afterward.
- **Acupoint definitions** (`AcupointDef`, `.tres` at `data/body_cultivation/acupoints/`) are the
  layout: 36 Minor (unlock 0), 12 Major (unlock 9), 12 Celestial (9 at unlock 18, 3 at unlock 27).
  Each names the `meridian_id` it trains, so acupoints and channels are linked by data.
- **Acupoints load from data, not code.** `AcupointDefaults` enumerates the generated `.tres`;
  `AcupointSet.synchronize(realm_id, capacity_bonus)` adds newly-unlocked points and re-derives
  capacity from the definition scaled by the meridian network's capacity bonus. Synchronize is
  idempotent and preserves stored essence, quality, and blocked flags.
- **Meridian refinement** is depth *within* the `strengthened` state. `MeridianState.refinement`
  rises via `MeridianNetwork.refine_meridian(id, max_refinement)`; the per-realm cap is module
  data, so core takes the cap as an argument. Each step adds `REFINE_POWER_STEP` of the channel's
  base power bonus. Refinement serializes with the network.
- **Action layer.** `BodyTraining.cultivate` distributes essence across open acupoints and grows
  quality toward the seed target; `BodyTraining.strengthen` spends the channel elixir to advance
  one channel through closed → open → expanded → strengthened → refine, and trains the acupoints
  on that meridian. `AcupointSet.busy` serializes the two so they cannot interleave.
- **Breakthrough** goes through `BodyAdvancement.try_breakthrough`, which validates
  `BodyBreakthroughCondition`, consumes the pill, then rolls against
  `breakthrough_chance + average_acupoint_quality`. Success grants `rewards` and advances;
  failure is a deviation — half progress, one random open acupoint blocked, a required channel
  damaged, integrity lost.
- **Core gates are cumulative.** `BodyBreakthroughCondition` calls `Breakthrough`'s
  `tribulation_ok` / `inside_world_ok` / `world_ok` / `ascension_ok` rather than re-deriving tier
  thresholds, so body progression and the ADR 0018-0021 gates cannot drift apart.
- **Items** are consumed through the `items` facade: `ItemsApi.has_item` / `consume_item`
  (all-or-nothing). `body_cultivation` therefore declares `items` as a dependency.

## Consequences

- Every one of the 30 realms has a seed; every seed's meridians resolve in the network and both of
  its items exist in content. `test_realm_seed_data.gd` and `test_body_training.gd` assert this,
  so a broken generation contract fails the gate instead of surfacing in play.
- All 60 acupoints are reachable: 36 by Mortal, 48 by Spirit, 57 by Immortal, 60 at Transcendent.
- Adding a realm is authoring a seed `.tres`; adding an acupoint is authoring a definition.
- Refinement is the depth axis beneath the four channel states, so late-game channel investment
  has somewhere to go without adding a fifth state.
- The action layer is a module API, not wired into `app/` yet — nothing calls `BodyTraining` or
  `BodyAdvancement` outside tests. The vertical slice still needs a caller.
