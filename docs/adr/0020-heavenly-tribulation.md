# 0020 Heavenly tribulation system (天劫)

- Status: Draft
- Date: 2026-10-02

## Context

ADR 0005 unified all cultivation on a 30-realm ladder (Mortal 1-9, Spirit 10-18, Immortal 19-27, Transcendent 28-30). ADR 0011/0012/0013 define three cultivation systems (Qi, Body, Mind). ADR 0014/0017 cover Dantian + Meridians for Mortal/Spirit tiers. ADR 0018 (Inside World) makes Immortal breakthroughs require tribulation survival; ADR 0019 (World Creation) will do the same for Transcendent. The breakthrough system (`core/breakthrough.gd`) currently advances realms with no risk at high tiers — tribulation is the challenge that makes Immortal and Transcendent breakthroughs dangerous. This is a **core system change**: it extends `core/breakthrough.gd` and `core/actor.gd`.

## Decision

### Trigger

- Tribulation triggers on breakthrough at realm 19+ (Immortal and Transcendent tiers only).
- Mortal/Spirit breakthroughs (realms 1-18) are unaffected — pill + comprehension only (ADR 0011).

### Tribulation types

Six types, aligned to cultivation path and tier:

| Type | Chinese | Tests | Primary defense |
|---|---|---|---|
| Lightning | 雷劫 | Body + Qi | Body cultivation, qi shields |
| Heart Demon | 心魔劫 | Mind + Comprehension | Mind cultivation, comprehension |
| Karmic | 因果劫 | Dao heart + Relationships | Past actions, relationship score |
| Elemental | 元素劫 | Element mastery + Control | Elemental affinity, artifacts |
| Spatial | 空间劫 | Inside world stability | Inside world `stability` (ADR 0018) |
| Temporal | 时间劫 | Comprehension + Will | Mind cultivation, comprehension |

- **Immortal tier** (19-27): Lightning, Heart Demon, Elemental, Spatial.
- **Transcendent tier** (28-30): All six; Temporal replaces Spatial as primary.
- Type is chosen by dominant cultivation path: body cultivators face stronger Lightning, mind cultivators face stronger Heart Demon.

### Structure (4 phases)

1. **Warning** — heavens gather; cultivator prepares (seconds to minutes of real time).
2. **Trial** — 3-9 waves (scales with realm); each wave tests one aspect.
3. **Climax** — final strike; most dangerous; tests all aspects simultaneously.
4. **Aftermath** — success (rewards) or failure (consequences).

### Difficulty scaling

- **Realm**: higher realm = more waves, harder strikes.
- **Cultivation path**: dominant path increases matching tribulation type intensity.
- **Karmic debt**: past actions (kills, betrayals) increase Karmic Tribulation difficulty.
- **Preparation**: formations, pills, allies, environment, artifacts reduce difficulty (see below).

### Preparation mechanics

- **Formations**: defensive formations reduce tribulation damage (percentage reduction).
- **Pills**: tribulation-specific pills (Lightning Resistance, Heart Calm, etc.) grant temporary immunity or resistance.
- **Allies**: allies can help defend but increase tribulation difficulty (more targets for heavens).
- **Environment**: sacred grounds reduce difficulty; cursed grounds increase it.
- **Artifacts**: artifacts can absorb or deflect tribulation strikes (durability cost).

### Rewards (success)

- **Tribulation essence**: rare resource; used in Immortal/Transcendent crafting.
- **Heavenly blessing**: temporary buff (cultivation speed +X% for Y days).
- **Dao insight**: permanent comprehension boost.
- **Tribulation mark**: permanent counter; prestige + minor bonus per mark.

### Failure consequences

- **Injury**: damaged body/qi/mind (recoverable via pills/rest).
- **Cultivation deviation**: progress loss + meridian damage (ADR 0014).
- **Dao heart damage**: permanent comprehension penalty (recoverable only at Transcendent tier).
- **Death**: possible at realm 25+ without preparation; rare.

### Interactions with 3 cultivation systems

- **Qi** (ADR 0011): qi shields absorb lightning; qi deviation risk if shield breaks.
- **Body** (ADR 0012): body cultivation reduces lightning damage; body techniques deflect strikes.
- **Mind** (ADR 0013): mind cultivation resists heart demons; comprehension reduces illusion duration.

### Inside World / World Creation integration

- **Immortal breakthrough**: tribulation tests inside world `stability` (ADR 0018); failure damages the world (`size` and `stability` reduced).
- **Transcendent breakthrough**: tribulation tests world laws and dao comprehension (ADR 0019); failure damages created world.

### Data model

- `TribulationState`: `type`, `phase`, `wave`, `difficulty`, `preparation` (Dictionary).
- Stored on `Actor` during tribulation; cleared after resolution.
- Serializable in `Actor.to_dict()` / `from_dict()` with schema version bump (v1 → v2, aligned with ADR 0018).
- **Core** infrastructure — shared by all cultivation systems; module access via facade.

## Consequences

- **Core change**: `core/breakthrough.gd` extended with tribulation gate; `core/actor.gd` gains `tribulation_state` field; schema bumps to v2.
- Builds on ADR 0014 (Dantian/Meridians — failure damages both) and ADR 0018 (Inside World — failure damages world).
- Cross-system synergy: all 3 cultivation paths (ADR 0011/0012/0013) feed into tribulation defense; no direct module-to-module references (facade-only).
- Preparation creates acquisition gaps: tribulation pills, formations, artifacts, sacred grounds.
- Death at high realms gives Immortal/Transcendent breakthroughs real stakes — preparation is mandatory, not optional.
- ADR 0019 (World Creation) builds on this: Transcendent tribulation tests created world laws.
