# 0016 Thức Hải and mind meridian system (Thức Hải + Mạch)

- Status: Accepted
- Date: 2026-10-02

## Context

Mind Cultivation (ADR 0013) needs a storage vessel and a channel mechanism. The **Thức Hải** (Sea of Consciousness) is the mind's energy reservoir, located in the upper dantian/head region. It stores mind power and is the mind-cultivation analogue of the Đan Điền (ADR 0014) and Huyệt (ADR 0015). The shared **Mạch** (Meridian) system (ADR 0017) surrounds the body and carries all three cultivation energies; this ADR defines how mind cultivation specifically interacts with it. No `core/` or `contracts/` changes — this extends the `mind_cultivation` module only.

## Decision

### Sea of Consciousness tiers

- **Shallow Sea** (淺海) — realms 1-9 (Mortal): basic mind power storage, limited capacity.
- **Deep Sea** (深海) — realms 10-18 (Spirit): refined mind power, unlocks at Spirit tier, much larger capacity.
- **Vast Sea** (瀚海) — realms 19-30 (Immortal/Transcendent): upper world-seed anchor, largest capacity.

### Sea mechanics

- **Single reservoir**: The sea reads/mutates the actor's `mind_power` `ResourcePool` (ADR 0013). The sea owns structural tier, clarity, turbulence, purity, and trained stage; the pool owns current/maximum.
- **Capacity**: `structural_capacity * (1 + meridian_capacity_bonus)`. Never persists equipment-inflated maximum as permanent structure.
- **Clarity**: Affects mental technique effectiveness and deviation resistance. Improved by cultivation, sea catalyst, and breakthroughs. Target: `Q(R) = 0.40 + 0.015*(R-1)`.
- **Purity**: Bounded refinement of stored energy. Improved by cultivation and sea catalyst. Target: `U(R) = 0.45 + 0.015*(R-1)`.
- **Turbulence**: Failed breakthroughs cause turbulence (confusion, hallucinations), reducing effectiveness until calmed. Mind cultivators use **meditation** to calm turbulence — a unique recovery mechanism not available to qi/body cultivators.
- **Effective capacity**: `structural_capacity * (1 - turbulence * 0.5)`. Turbulence reduces usable capacity but does not erase stored mind power.

### Mind + Meridian interaction

Mind cultivation uses meridians differently from qi/body:

- **Flow** — mind power flows through meridians → extends spiritual sense range.
- **Expansion** — meridian expansion increases sea capacity and mind technique range.
- **Strengthening** — meridian strengthening increases mind technique power and mental defense.
- **Sensing** — mind cultivation can sense meridian state: detect blockages, damage, and flow quality.

### Breakthrough challenges (Mortal + Spirit tiers)

Each mind breakthrough requires: full sea + required meridians strengthened + comprehension threshold + clarity threshold + purity threshold + pill.

- **Deviation risk**: if meridians are not fully prepared or clarity is low, mental deviation risk increases.
- **Failed breakthrough**: sea turbulence + meridian damage.
- **Cultivation speed**: `base * (1 + meridian_strengthening_bonus) * realm_profile_factor`.

### Realm profile factors

- **P**: Reference power budget. Mortal `1 × 1.25^(local-1)`, Spirit `8 × 1.22^(local-1)`, Immortal `55 × 1.20^(local-1)`, Transcendent `330 × 1.35^(local-1)`.
- **C**: Capacity factor = `P^0.85`.
- **F**: Throughput factor = `P^0.40`.
- **T**: Technique factor = `P^0.55`. Used by `MindProvider` for mental attack and technique power.

## Consequences

- Sea tiers are data-driven (realm-gated `.tres`), not code changes — consistent with ADR 0001/0005.
- `mind_power` pool maximum is set by sea tier + meridian expansion; clarity and turbulence are structural properties of the sea component.
- Meridian interaction is read-only from the mind module's perspective: mind cultivation consumes meridian state (expansion, strengthening) but does not mutate it — mutation happens in the qi/body modules (ADR 0014/0015).
- Meditation (turbulence recovery) is a mind_cultivation module ability; no cross-module dependency.
- Module depends only on `core` + `contracts`; no new facade dependencies.
- Breakthrough failure consequences (turbulence + meridian damage) are resolved through existing status/meridian systems, not new core mechanics.
- The sea is serialized in `Actor.to_dict()`/`from_dict()` with schema version 3.
