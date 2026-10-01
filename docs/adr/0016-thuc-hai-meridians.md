# 0016 Thức Hải and mind meridian system (Thức Hải + Mạch)

- Status: Accepted
- Date: 2026-10-02

## Context

Mind Cultivation (ADR 0013) needs a storage vessel and a channel mechanism. The **Thức Hải** (Sea of Consciousness) is the mind's energy reservoir, located in the upper dantian/head region. It stores mind power and is the mind-cultivation analogue of the Đan Điền (ADR 0014) and Huyệt (ADR 0015). The shared **Mạch** (Meridian) system (ADR 0014) surrounds the body and carries all three cultivation energies; this ADR defines how mind cultivation specifically interacts with it. No `core/` or `contracts/` changes — this extends the `mind_cultivation` module only.

## Decision

### Sea of Consciousness tiers

- **Shallow Sea** (淺海) — realms 1-9 (Mortal): basic mind power storage, limited capacity.
- **Deep Sea** (深海) — realms 10-18 (Spirit): refined mind power, unlocks at Spirit tier, much larger capacity.
- **Vast Sea** (瀚海) — reserved for Immortal/Transcendent (out of scope; discussed later).

### Sea mechanics

- **Capacity**: scales with realm and comprehension. Mind techniques consume from the sea (`mind_power` pool, ADR 0013).
- **Clarity**: affects mental technique effectiveness and deviation resistance. Improved by qi cultivation, pills, and breakthroughs.
- **Turbulence**: failed breakthroughs cause turbulence (confusion, hallucinations), reducing effectiveness until calmed. Mind cultivators use **meditation** to calm turbulence — a unique recovery mechanism not available to qi/body cultivators.

### Mind + Meridian interaction

Mind cultivation uses meridians differently from qi/body:

- **Flow** — mind power flows through meridians → extends spiritual sense range.
- **Expansion** — meridian expansion increases sea capacity and mind technique range.
- **Strengthening** — meridian strengthening increases mind technique power and mental defense.
- **Sensing** — mind cultivation can sense meridian state: detect blockages, damage, and flow quality.

### Breakthrough challenges (Mortal + Spirit tiers)

Each mind breakthrough requires: full sea + required meridians strengthened + comprehension threshold + clarity threshold + pill.

- **Deviation risk**: if meridians are not fully prepared or clarity is low, mental deviation risk increases.
- **Failed breakthrough**: sea turbulence + meridian damage.
- **Cultivation speed**: `base * (1 + meridian_strengthening_bonus) * realm_multiplier`.

## Consequences

- Sea tiers are data-driven (realm-gated `.tres`), not code changes — consistent with ADR 0001/0005.
- `mind_power` pool maximum is set by sea tier + meridian expansion; clarity and turbulence are status effects on `Actor` (ADR 0013 pattern).
- Meridian interaction is read-only from the mind module's perspective: mind cultivation consumes meridian state (expansion, strengthening) but does not mutate it — mutation happens in the qi/body modules (ADR 0014/0015).
- Meditation (turbulence recovery) is a mind_cultivation module ability; no cross-module dependency.
- Module depends only on `core` + `contracts`; no new facade dependencies.
- Breakthrough failure consequences (turbulence + meridian damage) are resolved through existing status/meridian systems, not new core mechanics.
