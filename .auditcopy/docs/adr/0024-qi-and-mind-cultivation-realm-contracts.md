# 0024 Qi and mind cultivation realm contracts

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0023 gave Body Cultivation a complete seeded progression: a per-realm contract, an
acupoint data layer, meridian refinement, a training action layer, and a breakthrough that
consumes real content. Qi (ADR 0011/0014) and Mind (ADR 0013/0016) had only storage and stat
providers — no breakthrough condition, no content, and no way to spend a realm. The three
major systems were not symmetrical, and only one of them could actually be played.

## Decision

- **One seed resource per system, same shape as the body contract.** `QiRealmSeed` and
  `MindRealmSeed` (`.tres` per realm under `data/qi_cultivation/realms/` and
  `data/mind_cultivation/realms/`) declare the destination realm's pill, training item,
  progress and comprehension thresholds, storage quality/fill requirements, storage tier,
  required meridians, required channel state, refinement cap, storage capacity, and rewards.
- **Storage tier follows the realm being entered; channel requirements follow the realm
  being left.** A seed never demands a meridian that only unlocks at or after the target
  realm, so preparation is always achievable — but the vessel cultivated afterwards is the
  destination tier (qi: lower/middle/upper; mind: shallow/deep/vast).
- **The three systems differ in how hard they ask for channels.** Qi needs channels merely
  *open*; Mind needs them *strengthened*, matching ADR 0016's read-only-but-deep coupling to
  the meridian network. Body sits between them via acupoint quality.
- **Training is a module action layer, mirroring `BodyTraining`.** `QiTraining.cultivate`
  circulates qi into the dantian, scaling by realm power and the network's flow bonus, and
  refines dantian quality; `MindTraining.cultivate` fills the sea and sharpens clarity.
  `train_channel` on both spends the realm's elixir to walk one meridian a step
  (closed → open → expanded → strengthened → refine) and repairs a damaged channel.
  `MindTraining.meditate` is the mind system's unique recovery, calming sea turbulence.
- **Breakthrough is seeded and deviable, mirroring `BodyAdvancement`.**
  `QiBreakthroughCondition` / `MindBreakthroughCondition` validate the seed, then
  `QiAdvancement` / `MindAdvancement` spend the pill and roll against breakthrough chance
  plus storage quality. Failure is a deviation that is *system-specific*: qi scars the
  dantian (capacity −25%, quality halved) and burns a channel; mind clouds the sea
  (turbulence, halved clarity) and burns a channel. Both halve progress.
- **Channel comparison is ordered, not equality.** `MeridianState.meets(required)` compares
  against `STATE_ORDER` and treats a damaged channel as satisfying nothing, so "at least
  strengthened" works and a damaged channel can never pass a gate.
- **Tier gates stay in core.** Qi and Body call `Breakthrough.tier_gates_met`, so module
  code and the ADR 0018-0021 gates cannot drift apart. Mind delegates its high-tier anchor
  requirement to `MindAnchor` instead: the anchor R19 commits is that attempt's own outcome,
  so it cannot also be its precondition (ADR 0029).
- **Both modules now depend on `items`** (through the facade, for `has_item`/`consume_item`),
  matching the body module's declared dependency.
- **Generation is a tool, not hand-authoring.** `uv run python -m tools cultivation
  seed-systems` writes the 60 realm seeds and every item, recipe, boss, and domain they
  reference, never overwriting an authored file. `tools data audit` is the acceptance test.

## Consequences

- All three major systems now have the same progression shape: seed → prepare → train →
  attempt → advance or deviate. A player can start a qi or mind run today and hit real
  gates at every realm.
- The three systems diverge meaningfully under identical machinery: qi is the forgiving
  channel path with a scarable vessel, mind is the deep-channel path with a recoverable one,
  body is the many-small-pieces path. Cross-system comparison stays in realm ids.
- 540 generated resources (60 seeds plus their content) are validated by the same audit as
  the rest of the data, so a dangling item or unresolvable meridian fails `tools check`.
- Adding a fourth system is now a seed resource, a training/advancement pair, and one
  `seed-systems` entry — no new progression engine.
- The action layers are still module APIs. `app/` does not call `QiTraining`,
  `MindTraining`, `QiAdvancement`, or `MindAdvancement`; the vertical slice still needs a
  caller (DEF-0030).
