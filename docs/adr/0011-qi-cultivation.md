# 0011 Qi cultivation (Luyện Khí)

- Status: Draft
- Date: 2026-10-02

## Context

ADR 0003 established pluggable cultivation paths; ADR 0005 unified them on a shared 30-realm ladder. The game needs its first concrete path: **Qi Cultivation** — the classic energy system that fuels techniques, flight, and perception. It must coexist with future paths (body, soul, sword) and integrate with the existing `Actor`/`ActorStats`/`ResourcePool`/`StatProvider` framework without modifying `core/` or `contracts/`.

## Decision

- **Path**: `path_id: "qi_cultivation"`, 30 stage names aligned to the shared ladder (Qi Refining → Qi Condensation → Foundation → Core Formation → Nascent Soul → ...). Authored in `qi_path.gd`.
- **Resources** (`ResourcePool`): `qi` (path-specific energy pool, distinct from core `max_qi` vitals) and `qi_purity` (0–1 quality; affects technique effectiveness and alchemy).
- **Base attributes** (module-specific, stored in `ActorStats._base` alongside core's 7): `qi_affinity` (absorption), `qi_control` (precision/cost reduction), `dantian_capacity` (storage size).
- **Derived stats** (emitted by `QiProvider`): `qi_regen_rate`, `qi_absorption`, `technique_cost_reduction`, `technique_power`, `flight_speed`, `qi_sense_range`.
- **Progression**: `LadderProgression` (shared ladder). Breakthrough requires: full qi pool, comprehension ≥ threshold, breakthrough pill (consumed). Failure risks qi deviation (progress loss + `qi_purity` penalty).
- **Stat provider**: `QiProvider` implements `StatProvider`; reads base + core attributes, realm rank, and `qi_purity`. Pure, no scene tree.
- **Module**: `game/src/modules/qi_cultivation/` — `api.gd` (facade), `provider.gd`, `stats.gd`, `qi_path.gd`.
- **Interactions**: combat reads `qi` pool for techniques; alchemy reads `qi_purity` for success; realm tier gates advanced techniques (tier ≥ 2 flight, tier ≥ 3 qi sense).

## Consequences

- First concrete path; validates the pluggable architecture (ADR 0003/0005).
- `qi` pool is distinct from core `MAX_QI` — path-specific energy system coexists with future paths.
- Combat/alchemy consume `QiProvider` stats via `api.gd` facade; no direct module-to-module references.
- Breakthrough failure creates a risk/reward loop with alchemy (purification pills).
- Future paths follow the same pattern: `stats.gd` + `provider.gd` + `*_path.gd` + `api.gd`.
- No `core/` or `contracts/` changes; self-contained and testable headless.
