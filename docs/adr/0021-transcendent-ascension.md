# 0021 Transcendent ascension system (飞升)

- Status: Draft
- Date: 2026-10-02

## Context

The shared ladder (ADR 0005) defines Transcendent tier as realms 28–30. ADR 0018 (Inside World) covers Immortal-tier internal world-building; ADR 0019 (World Creation) covers world formation at Transcendent entry; ADR 0020 (Heavenly Tribulation) covers tribulation mechanics. This ADR defines the **final tier mechanics**: ascension stages, dao comprehension, and the transition from mortal cultivation to transcendent existence. It is a **core system change** — it modifies `Actor`, adds a new `AscensionState` type, and introduces dao as a cross-cutting mechanic affecting all three cultivation paths (ADR 0011/0012/0013).

## Decision

### Ascension stages (realms 28–30)

- **Stage 1 — Dao Comprehension (悟道, realm 28)**: comprehend a single dao. Requires: World Creation active (ADR 0019), tribulation survival (ADR 0020), comprehension threshold met.
- **Stage 2 — Dao Fusion (合道, realm 29)**: fuse dao with self. Requires: stable world, dao fusion ritual, tribulation, advanced comprehension.
- **Stage 3 — Transcendence (超越, realm 30)**: transcend the mortal plane. Requires: Great World, dao transcendence, final tribulation, ultimate comprehension.

### Dao comprehension system

- **Dao types** (data-driven, `DaoDef` resource): Sword, Blade, Spear, Fire, Water, Wood, Metal, Earth, Thunder, Wind, Ice, Space, Time, Life, Death, Soul, Formation, Alchemy, Beast, Karma, plus original concepts.
- **Comprehension levels**: Awakening → Understanding → Mastery → Fusion → Transcendence (5 ranks, stored per dao).
- **Dao effects**: unlock abilities, modify techniques, change mechanics (e.g., Fire dao amplifies fire techniques, reduces water cost).
- **Dao conflicts/synergies**: defined in `DaoDef` (conflict: Fire/Water; synergy: Sword/Metal). Conflicting daos penalize comprehension speed; synergistic daos boost it.

### Ascension rewards

- **Stage 1**: dao abilities unlocked, technique modification, comprehension boost.
- **Stage 2**: dao fusion (techniques become dao-infused), world expansion.
- **Stage 3**: transcendence — become a transcendent being; create life, shape reality.

### Transcendent abilities (post-ascension)

Reality shaping (minor warping within your world), life creation, dao projection (across worlds), world ascension (elevate world tier), legacy (leave inheritances, artifacts, teachings).

### Interaction with three cultivation systems

- **Qi** (ADR 0011): qi becomes dao energy; techniques become dao techniques.
- **Body** (ADR 0012): body becomes dao body; physical laws bend to will.
- **Mind** (ADR 0013): mind becomes dao mind; comprehension becomes omniscience within domain.

### Final tribulation (realm 30)

Combines all tribulation types (ADR 0020). Tests body, qi, mind, dao, world, comprehension. Failure: cultivation deviation, world damage, or death. Success: transcendence.

### Post-transcendence (endgame)

Create/manage multiple worlds, interact with other transcendent beings, shape the cosmos, leave a legacy.

### Data model

- `AscensionState` (RefCounted): `stage` (int), `dao_type` (StringName), `dao_level` (int), `comprehension` (float), `abilities` (Array[StringName]).
- Stored on `Actor.ascension` — serialized in `Actor.to_dict()`/`from_dict()` with schema version bump to 2.
- `DaoDef` resource: `id`, `display_name`, `conflicts` (Array[StringName]), `synergies` (Array[StringName]), `effects` (Array[DaoEffect]).

## Consequences

- **Core change**: `Actor` gains `ascension` field; `SCHEMA_VERSION` bumps to 2; save migration required.
- **Cross-cutting**: dao comprehension affects all three paths — modules read dao state via `Actor.ascension`, not direct module references.
- **Depends on**: ADR 0019 (World Creation) for world requirement, ADR 0020 (Tribulation) for tribulation mechanics.
- **Endgame content**: post-transcendence is a new game phase; world management and legacy systems are future modules.
- **Data-driven**: dao types and effects are content (`DaoDef` `.tres`), not code — adding a dao is a data change.
- **No `contracts/` change**: `AscensionState` lives in `core/` alongside `Actor`; `DaoDef` is a module-level resource.
