# 0019 World creation system (创世)

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0005 unified all cultivation on a 30-realm ladder (Mortal 1-9, Spirit 10-18, Immortal 19-27, Transcendent 28-30). ADR 0011/0012/0013 defined the three cultivation systems (Qi, Body, Mind); ADR 0014/0017 built the shared Dantian + Meridian network. ADR 0018 (Inside World) gives Immortal-tier cultivators an internal pocket dimension anchored to their body. The Transcendent tier (realms 28-30) needs its own pinnacle system: **World Creation** — the ability to create actual worlds/realms, not merely internal pockets. This is the most complex feature in the game: it subsumes all three cultivation systems, builds on the Inside World anchor, and introduces spatial, temporal, elemental, physical, life, and qi laws as first-class data. This ADR covers Transcendent tier only.

## Decision

### World tiers (aligned to Transcendent realms)

| Realm | Tier | Name | Description |
|---|---|---|---|
| 28 | Micro World (微世界) | `world_tier_micro` | Room-sized; 1 spatial layer; simple laws; no life |
| 29 | Small World (小世界) | `world_tier_small` | Terrain + weather; 2-3 layers; basic life; elemental cycles |
| 30 | Great World (大世界) | `world_tier_great` | Continents + civilizations; 4+ layers; complex ecosystems; full law customization |

World tier is stored on `WorldState.tier` and gates all property ranges, law slots, and functions.

### World properties

Each world has six law groups, all data-driven (`WorldLawDef` resources):

1. **Spatial**: `size` (radius in abstract units), `dimensions` (default 3; Great World can add pocket dimensions), `stability` (0-1; below 0.3 world takes damage), `layers` (array of `WorldLayerDef`: surface, underground, heaven, void). Micro: 1 layer. Small: 2-3. Great: 4+.
2. **Temporal**: `time_flow_rate` (0.1x-100x relative to outside; cultivation accelerator), `time_stability` (0-1; low stability causes time surges/loops), `time_loops` (Great World only: cultivators can create closed time loops for accelerated training).
3. **Elemental**: `dominant_elements` (up to 3 element ids from ADR 0004), `elemental_balance` (0-1; affects weather/seasons), `elemental_cycles` (season length, weather patterns — data-driven).
4. **Physical**: `gravity` (0.1x-10x), `energy_density` (qi richness multiplier), `material_hardness` (affects construction/combat), `natural_rules` (custom flags: e.g., "no fire techniques", "double gravity zone").
5. **Life**: `allowed_life_forms` (plant/beast/humanoid/elemental), `evolution_speed` (0.1x-10x), `intelligence_ceiling` (0-1; caps NPC cultivation potential).
6. **Qi**: `qi_density` (0.1x-100x), `qi_type` (spiritual/demonic/natural — determines what cultivators benefit), `qi_cycles` (qi tide schedule — e.g., "qi surges at dawn").

**World Will**: `will_strength` (0-1) — the creator's mind cultivation (ADR 0013) determines initial will. Will decays over time unless reinforced by mind cultivation. Low will → law drift, instability, rebellion (inhabitants resist creator's edicts).

### World Creation process (5 steps)

Creation is a multi-step ritual, not a single action. Each step consumes resources and has failure risk.

1. **World Seed** — condense from qi (ADR 0011) + dao comprehension (ADR 0013 `dao_heart`) + a `WorldSeed` item (rare drop or crafted). Consumes 50% of all three resource pools. Failure: seed collapses, item lost.
2. **Space Opening** — tear open space using the Inside World (ADR 0018) as anchor. Requires stable Inside World (stability ≥ 0.7). Consumes qi + body integrity. Failure: spatial backlash damages Inside World.
3. **Law Imprinting** — imprint elemental, physical, and temporal laws. Each law slot costs qi + mind power. Number of slots = f(world tier): Micro 3, Small 6, Great 10. Failure: law rejection causes instability.
4. **Stabilization** — anchor the world to the creator's Upper Dantian (ADR 0014). Consumes qi + body + mind. Requires all three pools ≥ 80%. Failure: world collapses; Inside World damaged.
5. **Life Seeding** (optional) — seed life forms. Costs qi + life-element affinity. Micro: plants only. Small: + beasts. Great: + humanoids. Failure: life withers, qi refunded 50%.

**Tribulation**: heavenly tribulation strikes during Step 2 and Step 4. Tribulation power scales with world tier + law complexity. Defense = body cultivation + world will + Inside World stability. Failure: world instability (reduced size/laws until stabilized via maintenance).

### World functions

| Function | Min Tier | Description |
|---|---|---|
| Cultivation | Micro | Enter world to cultivate with customized `time_flow_rate` + `qi_density` |
| Production | Micro | Grow resources, raise beasts, build structures (costs qi upkeep) |
| Combat | Small | Pull enemies into world; creator's will grants law advantage (e.g., +gravity for enemies) |
| Defense | Micro | Retreat into world; enemies must breach world barrier (stability check) |
| Civilization | Great | Create intelligent beings who cultivate, build, and worship creator (worship → will regeneration) |
| Dao comprehension | Micro | Creating/managing world deepens `dao_heart` (ADR 0013) — passive + active comprehension gain |
| World evolution | Small | Worlds can evolve (grow size, add layers, unlock law slots) via qi investment + tribulation survival |
| Sub-worlds | Great | Spawn sub-worlds (nested dimensions) — each is a separate `WorldState` linked to parent |

### Interactions with the three cultivation systems

- **Qi (ADR 0011)**: raw material for creation/maintenance. `qi_density` in world amplifies cultivation speed. World qi type determines which cultivators benefit.
- **Body (ADR 0012)**: provides physical laws and material foundation. Body cultivation level caps `material_hardness` + `gravity` limits. Body damage → world stability penalty (body is the anchor).
- **Mind (ADR 0013)**: controls world will, law imprinting precision, and evolution direction. `will` stat determines `will_strength`. Mind cultivation regenerates will. `dao_heart` gates law complexity.

### World Creation requirements

- Transcendent tier (realm 28+)
- Stable Inside World (ADR 0018, stability ≥ 0.7)
- Dao comprehension threshold (`dao_heart` ≥ tier-specific value)
- `WorldSeed` item (consumed)
- All three resource pools ≥ 80%
- Tribulation survival

### Breakthrough challenges (Transcendent tier)

Each Transcendent breakthrough (28→29, 29→30) requires:
- Stable world of current tier
- Required world laws imprinted (defined in `RealmDef`)
- Dao comprehension ≥ threshold
- Tribulation survival (power scales with target tier)

**Failed breakthrough**: world instability — size reduced 25%, 1-2 law slots locked until stability restored via maintenance (qi investment + time). Inside World (ADR 0018) also damaged.

### World management (ongoing)

- **Upkeep**: worlds drain qi per tick (rate = f(tier, size, laws)). If qi upkeep unpaid → stability decays → law drift → potential collapse.
- **Damage**: external attacks (enemy world-breakers) or internal instability (low will, law conflicts) reduce stability. Stability 0 → world collapse (Inside World damaged, inhabitant fate: scattered/killed).
- **Merge**: two worlds can merge (diplomacy or conquer). Result: combined size, dominant creator's laws, merged inhabitants. Requires both creators' consent OR conqueror's will ≥ defender's will × 1.5.
- **Ascension**: Micro → Small → Great. Requires qi investment + tribulation + law slots filled. Ascension adds layers, law slots, life forms.

### Data model

- `Actor.world: WorldState` — stored on Actor (new field, schema version bump to 2).
- `WorldState`: `tier`, `size`, `stability`, `will_strength`, `laws: Array[WorldLawState]`, `layers: Array[WorldLayerState]`, `inhabitants: Array[InhabitantRef]`, `resources: Dictionary`, `upkeep_rate`, `time_flow_rate`.
- `WorldLawState`: `law_id`, `group` (spatial/temporal/elemental/physical/life/qi), `value`, `locked: bool`.
- `WorldLayerState`: `layer_id`, `name`, `size_ratio`, `laws: Array[StringName]`.
- `InhabitantRef`: `inhabitant_id`, `type` (plant/beast/humanoid/elemental), `count`, `loyalty` (0-1).
- Serializable in `Actor.to_dict()` / `from_dict()` with schema version 2. Migration v1→v2 adds `world` field (default: null).
- World contents (items, structures, beings) stored as nested data inside `WorldState` — not as separate entities in the main world.

## Consequences

- **Core change**: `Actor` gains a `world: WorldState` field — schema version bump to 2 with migration. This is the first `core/` change since ADR 0001.
- **Module**: `game/src/modules/world_creation/` — `api.gd` (facade), `world_state.gd`, `world_law.gd`, `creation.gd` (5-step process), `tribulation.gd`, `management.gd` (upkeep/damage/merge/ascension). Depends on `core/` + `contracts/` + reads Inside World via facade.
- **Cross-system**: all three cultivation systems (ADR 0011/0012/0013) feed into world creation — qi is material, body is foundation, mind is control. No direct module-to-module references; all via `api.gd` facades.
- **Inside World dependency**: ADR 0018 is a hard prerequisite. World Creation reads Inside World stability via facade; damages it on failure.
- **Save schema**: v1→v2 migration adds `world` field. Existing saves get `world: null` (no world).
- **Content authoring**: world tiers, law definitions, life forms, and tribulation parameters are data (`.tres`) — adding new laws or tiers is authoring, not code.
- **Performance**: world tick (upkeep, stability, inhabitant simulation) runs on a separate tick from main game loop; Micro World ticks every 10s, Small every 5s, Great every 1s (configurable).
- **Combat integration**: pulling enemies into a world is a combat action gated by world tier + will. Combat system reads world laws via facade to apply modifiers.
- **Civilization**: Great World inhabitants can cultivate (simplified path), build structures (production bonus), and worship creator (will regeneration). Inhabitant AI is data-driven, not full NPC AI.
- **World evolution**: ascension and sub-worlds mean the system is extensible — new tiers or nested worlds are data, not code.
