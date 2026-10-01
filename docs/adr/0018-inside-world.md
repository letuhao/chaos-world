# 0018 Inside world system (内世界)

- Status: Draft
- Date: 2026-10-02

## Context

ADR 0005 unified all cultivation paths on a 30-realm ladder (Mortal 1-9, Spirit 10-18, Immortal 19-27, Transcendent 28-30). ADR 0011/0012/0013 define three cultivation systems (Qi, Body, Mind) that store energy in different reservoirs (Đan Điền, Huyệt, Thức Hải). ADR 0014/0017 define the Dantian storage tiers and shared meridian network for Mortal + Spirit tiers. At Immortal tier (realms 19-27), cultivators create an **Inside World** — a pocket dimension within their body that serves as storage, cultivation accelerator, and tactical domain. This ADR defines that system; Transcendent tier (World Creation) is ADR 0019.

## Decision

### World tiers (aligned to Immortal realms 19-27)

| Tier | Realms | Name | Description |
|---|---|---|---|
| 1 | 19-21 | **Seed World** (種子世界) | Tiny spark of space in the Dantian; barely stable; minimal storage |
| 2 | 22-24 | **Pocket World** (洞天世界) | Small stable space; stores objects and qi; time flow begins |
| 3 | 25-27 | **Inner World** (內世界) | Fully formed world with own laws; supports life and production |

### Properties

- `size`: spatial volume; scales with realm; determines storage capacity.
- `stability` (0-1): affects storage safety and collapse risk; low stability risks item/qi loss.
- `qi_density`: ambient qi density; multiplies cultivation speed inside the world.
- `time_flow`: time ratio inside vs. outside (1:1 at Seed, up to 1:10 at Inner World).
- `laws`: elemental affinities and physical rules; gate advanced functions (production, life).

### Functions

- **Storage**: items, qi, and living beings (capacity = `size * stability`).
- **Cultivation**: cultivate inside for accelerated time (`time_flow * qi_density` multiplier).
- **Combat**: pull enemies inside for tactical advantage (enemy stats penalized by world laws).
- **Production**: grow herbs, mine ores, raise beasts (requires `laws` with matching elemental affinity).
- **Defense**: retreat into the world to escape danger (requires `stability >= 0.5`).

### Creation

- Requires: Immortal tier breakthrough (realm 19) + **World Seed** (世界种子) item.
- Process: stabilize a space within the Dantian using qi + comprehension.
- Failure: world collapse — Dantian damage (ADR 0014) + 1-3 meridians Damaged (ADR 0017).

### Expansion

- **Realms 19-21**: expand `size` and `stability` only.
- **Realms 22-24**: add elemental `laws` and `time_flow` (up to 1:5).
- **Realms 25-27**: add living beings, production, and `time_flow` (up to 1:10).

### Interactions with 3 cultivation systems

- **Qi** (ADR 0011): qi fuels stability and expansion; `qi_density` scales with `qi_purity`.
- **Body** (ADR 0012): body cultivation strengthens physical `laws` and increases `size` cap.
- **Mind** (ADR 0013): mind cultivation controls `time_flow` and `laws` precision.

### Breakthrough (Immortal tier)

- Each Immortal breakthrough requires: stable inside world (`stability >= threshold`) + required `laws` + comprehension + tribulation survival (ADR 0020).
- Failed breakthrough: world instability — `size` and `stability` reduced until stabilized (pills or cultivation).

### Data model

- `Actor.inside_world: InsideWorldState` — stored on Actor (core change).
- `InsideWorldState`: `tier`, `size`, `stability`, `qi_density`, `time_flow`, `laws` (Dictionary).
- Serializable in `Actor.to_dict()` / `from_dict()` with schema version bump (v1 → v2).
- **Core** infrastructure — shared by all cultivation systems; module access via facade.

## Consequences

- **Core change**: `Actor` gains `inside_world` field; schema version bumps to v2 with migration.
- Builds on Dantian (ADR 0014) and Meridian (ADR 0017) — creation failure damages both.
- Cross-system synergy: all 3 cultivation paths (ADR 0011/0012/0013) feed into world properties; no direct module-to-module references (facade-only).
- Storage, production, and combat-pull are new gameplay loops gated behind Immortal tier.
- World Seed item creates an acquisition gap (drop table / quest reward).
- Failed breakthrough now has a third recovery track: stabilize inside world (pills/cultivation).
- ADR 0019 (Transcendent) builds on this: World Creation extends Inside World to external reality.
