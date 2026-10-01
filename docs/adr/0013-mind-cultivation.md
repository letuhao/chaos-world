# 0013 Mind cultivation (Tu Niệm)

- Status: Accepted
- Date: 2026-10-02

## Context

The game needs a third major cultivation system alongside qi and body. Mind Cultivation is the mental/awareness refinement path — it fuels illusions, spiritual sense, and mental attacks, and it differentiates combat style through control, precision, and perception rather than raw power. It must plug into the existing actor/progression architecture (ADR 0001, 0003, 0005) without touching `core/` or `contracts/`.

## Decision

- **Path definition**: `path_id: "mind_cultivation"`, display name "Mind Cultivation". 30 stage names aligned to the shared ladder (ADR 0005/0006): Mind Awakening, Focus, Clarity, Insight, Enlightenment, ... (full array in `mind_path.gd`).
- **Resources** (`ResourcePool`): `mind_power` (mental energy pool, fuels techniques) and `awareness` (perceptual acuity, affects detection/crit/dodge).
- **Base attributes** (module-specific, stored in `ActorStats._base` alongside core's 7): `perception` (sensory/extrasensory awareness), `mental_clarity` (resistance to illusions/confusion). `will` (core, ADR 0001) is amplified by mind cultivation; `dao_heart` (core derived stat) is primarily sourced from mind cultivation via provider.
- **Derived stats** (emitted by `MindProvider`): `mental_attack`, `mental_defense`, `spiritual_sense_range`, `critical_chance`, `dodge_chance`, `illusion_resistance`, `mind_technique_power`, `comprehension_bonus`.
- **Progression**: `LadderProgression` (shared ladder, ADR 0005). Breakthrough requires: mind_power pool full, comprehension threshold met, mental_clarity threshold met (low deviation risk), and a breakthrough pill item. Failure causes mental deviation — confusion, hallucinations, dao heart damage.
- **Stat provider**: `MindProvider` implements `StatProvider` (ADR 0002); emits derived stats from base attributes + realm multipliers + affinities.
- **Module structure**: `game/src/modules/mind_cultivation/` — `api.gd` (facade), `provider.gd` (`MindProvider`), `stats.gd` (stat/resource id constants), `mind_path.gd` (`CultivationPathDef` resource script).
- **Interactions**: mind cultivation fuels mental techniques (illusions, spiritual sense, mental attacks); combat style is control/precision/perception vs. qi/body's power; realm tier gates advanced techniques (mind reading, soul attack, dao heart projection); high perception improves loot discovery, hidden path finding, and trap detection; affects dialogue, discovery, and information systems.

## Consequences

- Adding mind cultivation = authoring a `CultivationPathDef` `.tres` + module scripts; no `core/` or `contracts/` change.
- `MindProvider` is registered in `app/` at boot alongside other providers (DIP, ADR 0002).
- Breakthrough deviation is a status effect on `Actor`, not a core mechanic.
- Mind cultivators share the 30-realm ladder with all other systems; cross-system gating uses realm ids.
- `dao_heart` becomes a contested derived stat — core computes it from `will`, mind cultivation amplifies it via provider contribution.
- Module depends only on `core` + `contracts`; no cross-module facade dependency.
