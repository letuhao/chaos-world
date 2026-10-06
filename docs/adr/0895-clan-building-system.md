# 0895 Clan building is a new module extending clan scaffolding

- **Status**: accepted
- **Supersedes**: none
- **Corrects**: none

## Context

The clan system at `game/src/modules/clan/` has 3 clans, a ledger, ranks, patronage/duty, and gates. Zero progression/construction — but the scaffolding is real. The program spans: race (heterosis), bloodline, clan, wife/husband collections, relationship system, social interactive enhancement, and dual cultivation. Clan building is the expression of clan progression.

## Decision

- **Clan building is a new module** at `game/src/modules/clan_building/` that extends the existing clan scaffolding.
- 5 building types, 3 levels each, a 5-level clan progression system, and a tech tree.
- Buildings are constructed with **materials** (earned through hunting/combat) and **contribution** (earned through standing).
- Buildings grant passive bonuses, new verbs, and capacity increases.
- The yin-yang counterpart is **upkeep**: each building costs contribution per day, and overextension (too many buildings for your clan level) halves all bonuses.
- **Registry deps**: `["contracts", "core", "clan", "social"]` — reads clan state from `clan`, moves regard through `social`.

## Buildings

5 building types, 3 levels each. Costs scale with level. Each building grants passive bonuses and unlocks verbs at higher levels.

| Building | Category | Base Materials | Base Contribution | Cost Scale | Base Upkeep |
|----------|----------|---------------|-------------------|------------|-------------|
| Hall of Ancestors | lineage | 100 | 50 | 1.5 | 5 |
| Training Grounds | combat | 120 | 60 | 1.5 | 6 |
| Storehouse | economy | 80 | 40 | 1.4 | 4 |
| Meditation Chamber | cultivation | 150 | 75 | 1.6 | 8 |
| Defensive Works | military | 200 | 100 | 1.7 | 10 |

**Cost formula:** `cost = base_cost × cost_scale^(level-1)`

Example (Hall of Ancestors): L1 = 100/50, L2 = 150/75, L3 = 225/112.

| Building | Level 1 | Level 2 | Level 3 |
|----------|---------|---------|---------|
| Hall of Ancestors | +5% standing gain | +10% standing gain, bloodline purity decay −10% | +15% standing gain, purity decay −20%, 5% chance to inherit founder technique fragment |
| Training Grounds | +5% combat experience | +10% combat experience, unlock **sparring** | +15% combat experience, unlock **war council** |
| Storehouse | +10% material drop rate | +20% material drop rate, unlock **clan market** | +30% material drop rate, unlock **clan vault** |
| Meditation Chamber | +5% cultivation speed | +10% cultivation speed, unlock **group meditation** | +15% cultivation speed, unlock **qi gathering array** |
| Defensive Works | +5% defense in clan territory | +10% defense, unlock **watchtower** | +15% defense, unlock **fortress** |

## Resources and Economy

- **Materials:** Earned through hunting/combat. Consumed permanently on construction. Never purchasable — ties building to the core loop.
- **Contribution:** Earned by members through standing (1:1 exchange). Capped at 100/day/member.
- **Construction time:** L1 = 1h, L2 = 2h, L3 = 4h (game-time). No benefit during construction.

## Clan Level and Progression

`clan_level = 1 + floor(total_building_levels / 3)`. Max level 5 (requires 15 building levels).

| Clan Level | Total Building Levels | Member Capacity | Unlocks |
|------------|----------------------|-----------------|---------|
| 1 | 0–2 | 10 | Basic buildings |
| 2 | 3–5 | 15 | L2 buildings, tech tier 1 |
| 3 | 6–8 | 20 | L3 buildings, tech tier 2 |
| 4 | 9–11 | 25 | Tech tier 3 |
| 5 | 12–15 | 30 | Tech tier 4 |

## Tech Tree

Researched with materials + contribution. Unlocked by clan level.

| Tech | Clan Level | Materials | Contribution | Effect |
|------|-----------|-----------|--------------|--------|
| Ancestral Records | 1 | 50 | 25 | +5% bloodline purity gain |
| Basic Training | 1 | 50 | 25 | +5% combat experience |
| Trade Routes | 1 | 50 | 25 | +5% material sell price |
| Lineage Ritual | 2 | 150 | 75 | Unlock **purification ritual** |
| Sparring Partners | 2 | 150 | 75 | Unlock **sparring** |
| Clan Market | 2 | 150 | 75 | Unlock **clan market** |
| Ancestral Echo | 3 | 300 | 150 | Chance to inherit founder technique |
| War Council | 3 | 300 | 150 | Clan-wide buff vs rivals |
| Clan Vault | 3 | 300 | 150 | Shared material storage |
| Qi Gathering Array | 4 | 500 | 250 | Passive qi regeneration |
| Group Meditation | 4 | 500 | 250 | Cultivate together for bonus |
| Fortress | 5 | 1000 | 500 | Defensible clan territory |
| Watchtower | 5 | 1000 | 500 | Early warning of rival attacks |

## Yin-Yang Counterparts

1. **Upkeep:** Each building costs `base_upkeep × level` contribution/day. Unpaid for 3 days → building inactive.
2. **Overextension penalty:** `total_building_levels > clan_level × 3` → all bonuses halved.
3. **Construction time:** No benefit during construction (1–4h).
4. **Maintenance decay:** 30 days unpaid upkeep → building loses 1 level.
5. **Rival sabotage:** Rival clans can destroy 1 level of a random building. Prevented by Defensive Works.
6. **Rank discount:** Head 25%, Heir 15%, Core 10%, Inner 5%, Outer 0% construction cost reduction.
7. **Material scarcity:** Materials only from hunting/combat, never purchased.
8. **Contribution cap:** 100/day/member limits construction speed.

## Interaction with Existing Systems

- **Ranks:** Construction cost discounts (above).
- **Patronage:** Buildings fulfill patronage terms (Storehouse fulfills `quarter_share` and `store_access`).
- **Duty:** Members assigned to construction earn standing but cannot do other duty.
- **Standing → Contribution:** 1:1 exchange rate.
- **Social:** Construction moves regard (Meditation Chamber → cultivation NPCs, Defensive Works → military NPCs) through `SocialApi.apply_cause`.
- **Dual cultivation:** Meditation Chamber L2 unlocks **group dual cultivation**.
- **Bloodline:** Hall of Ancestors affects purity decay and inheritance.

## Implementation

**New module:** `game/src/modules/clan_building/`

| File | Class | Purpose |
|------|-------|---------|
| `api.gd` | `ClanBuildingApi` | Facade (12 methods) |
| `building_def.gd` | `BuildingDef` | Authored `.tres` resource |
| `building_catalog.gd` | `BuildingCatalog` | Loads building defs |
| `building_state.gd` | `BuildingState` | Versioned ledger |
| `building_gate.gd` | `BuildingGate` | Construction/research gates |
| `building_provider.gd` | `BuildingProvider` | Stat provider |
| `building_stats.gd` | `BuildingStats` | Stat id constants |
| `building_projection.gd` | `BuildingProjection` | Rebuilds from ledger |

**Data:** `game/data/clan_buildings/*.tres` (5 files)

**Facade methods:**
```gdscript
static func attach(actor: Actor) -> void
static func construct(actor: Actor, building_id: StringName) -> Dictionary
static func upgrade(actor: Actor, building_id: StringName) -> Dictionary
static func demolish(actor: Actor, building_id: StringName) -> bool
static func assign_duty(actor: Actor, building_id: StringName, member_id: StringName) -> Dictionary
static func pay_upkeep(actor: Actor) -> Dictionary
static func building_state(actor: Actor) -> Dictionary
static func building_summary(actor: Actor) -> Dictionary
static func can_construct(actor: Actor, building_id: StringName) -> Dictionary
static func clan_level(actor: Actor) -> int
static func tech_tree(actor: Actor) -> Dictionary
static func research(actor: Actor, tech_id: StringName) -> Dictionary
```

**BuildingDef resource:**
```gdscript
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var category: StringName = &""  # lineage | combat | economy | cultivation | military
@export var max_level: int = 3
@export var base_cost_materials: int = 100
@export var base_cost_contribution: int = 50
@export var cost_scale: float = 1.5
@export var base_upkeep: int = 5
@export var unlock_clan_level: int = 1
@export var bonuses: Array[Dictionary] = []  # [{level, stat_id, value, description}]
@export var verbs_unlocked: Array[Dictionary] = []  # [{level, verb_id, description}]
@export var tags: Array[StringName] = []
```

**BuildingState ledger** (stored under `actor.module_data["clan_building_state"]`):
```gdscript
{
    "version": 1,
    "buildings": { "hall_of_ancestors": {"level": 2, "active": true, "construction_progress": 0} },
    "techs_researched": [],
    "last_upkeep_paid": 0
}
```

**BuildingStats:**
```gdscript
const BUILDING_COUNT := &"clan_building_count"
const BUILDING_LEVEL := &"clan_building_level"
const CLAN_LEVEL := &"clan_level"
const UPKEEP_DUE := &"clan_upkeep_due"
const TECH_COUNT := &"clan_tech_count"
```

**Tests:** `game/tests/modules/clan_building/` — construction, upkeep, overextension, gate, provider suites.

## Consequences

- The clan system gains real progression — construction, tech tree, clan level.
- Buildings grant non-combat bonuses and unlock verbs; they never directly modify combat stats (ADR 0064's "recognition, never power" rule).
- Upkeep is non-negotiable — buildings without upkeep are a strict best response.
- Materials must come from hunting/combat, not a shop.
- Construction time removes the trade-off — instant construction is not allowed.
- Overextension penalty prevents constructing all 15 levels immediately.
- Ranks affect construction (cost discount).
- Buildings fulfill patronage terms.
- Meditation Chamber unlocks group dual cultivation.
- Hall of Ancestors affects bloodline purity decay and inheritance.
