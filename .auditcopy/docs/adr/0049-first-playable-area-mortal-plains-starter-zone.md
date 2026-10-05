# 0049 First playable area: Mortal Plains starter zone

- Status: Proposed
- Date: 2026-10-02

## Context

The world module (ADR 0045-0047) provides the data model and facade for 4 world tiers, 3 dao factions, and world content. But there is no runtime for entering a location, gathering resources, fighting bosses, or crafting pills. The backlog shows:

- DEF-0022: BossDef/DomainDef data exists but no spawning or loot rolls — R2+ is unobtainable in play
- DEF-0057: Realm pills are crafted from boss cores + herbs; without crafting, R2+ is blocked
- DEF-0058: No 2D world or combat — no player-controlled actor exists
- DEF-0030: Cultivation loop is unreachable — no screen calls the cultivation facades

The first playable area must unblock the core loop: **combat → hunting → cultivate → breakthrough**.

## Decision

### Mortal Plains Starter Zone

A single explorable location in the Mortal World (danger 1-3) that gives the player a place to hunt, gather, and fight without complex systems.

**Content:**
- 3-5 weak beast spawn zones (ironhide bear cub, venom serpent fledgling)
- 3-4 gatherable herb nodes (spirit herb, iron wood)
- 1 boss arena (ironhide bear) — drops guardian core for R2 pill
- 1 NPC elder (quest giver, explains cultivation basics)
- Entry/exit point to world map

**Systems needed:**
1. **Boss encounter runtime** (DEF-0022) — spawn bosses, roll loot, track domain clear
2. **Crafting production caller** (DEF-0057) — consume inputs, produce outputs
3. **2D player adapter** (DEF-0058) — CharacterBody2D wrapping an Actor
4. **Save round-trip** (DEF-0059) — persist Actor state

**Stat-check trial** (ADR 0008-style): enter domain, commit body integrity, roll boss.loot via ItemsApi.generate. No combat system needed for the first area.

### Priority Order

1. Boss encounter runtime — unblocks pill acquisition
2. Crafting production caller — unblocks R2+ progression
3. 2D player adapter — unblocks actual gameplay
4. Mortal Plains content — the first playable area
5. Save round-trip — unblocks persistence
6. Cultivation screen — unblocks player interaction

## Consequences

- **New module**: `game/src/modules/world_runtime/` — domain entry, boss spawn, loot roll, crafting production
- **App wiring**: `game/src/app/` — player actor, save/load, screen routing
- **Content**: Mortal Plains location, beast spawns, herb nodes, boss arena, NPC elder
- **Tests**: domain entry, boss loot, crafting production, save round-trip
- **Unblocks**: DEF-0022, DEF-0057, DEF-0058, DEF-0059, DEF-0030
