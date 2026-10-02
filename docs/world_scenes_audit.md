# World Scenes Audit Report

## What Was Missing

### Original Implementation
- **world_entry.gd**: Only had basic spawn point binding (`_spawn_point`). No NPC spawning, enemy spawn zones, resource node interaction, entry/exit point management, or tier-specific initialization.
- **World scenes** (`mortal_world.tscn`, `spirit_world.tscn`, `immortal_world.tscn`, `transcendent_world.tscn`): Empty shells with only a `SpawnPoint` Marker2D and a `WorldLabel` Label. No ground/terrain, no resource nodes, no enemy spawn zones, no navigation, no location markers, no entry/exit points, no tier-specific content.
- **Domain scenes**: Did not exist. No `.tscn` files for any of the four locations defined in `game/data/world/locations/`.

## What Was Enriched

### world_entry.gd
- Added `_npc_spawn_points`, `_enemy_spawn_zones`, `_resource_nodes`, `_entry_points`, `_exit_points`, `_location_markers` arrays
- Added `_collect_nodes()` helper to bind nodes from named groups
- Added `npc_spawn_points()`, `spawn_npc()` for NPC spawning
- Added `enemy_spawn_zones()`, `spawn_enemy()`, `random_enemy_spawn_position()` for enemy spawning
- Added `resource_nodes()`, `interact_with_resource()` for resource interaction
- Added `entry_points()`, `exit_points()`, `entry_position()`, `exit_position()` for entry/exit management
- Added `location_markers()` for POI queries
- Added `tier_id()`, `tier_display_name()`, `realm_range()`, `is_realm_in_tier()` for tier-specific data
- Added `summary()` for debugging and testing

### World Scenes
Each world scene now includes:
- **Ground**: ColorRect with tier-appropriate color (green for Mortal, blue for Spirit, gold for Immortal, violet for Transcendent)
- **NavigationRegion2D**: For pathfinding
- **SpawnPoint**: Player spawn location
- **WorldLabel**: Display name
- **EntryPoints/ExitPoints**: Marker2D nodes for entering/exiting the world
- **NPCSpawnPoints**: Marker2D nodes for NPC placement
- **EnemySpawnZones**: Area2D nodes with CollisionShape2D for enemy spawning
- **ResourceNodes**: Area2D nodes with CollisionShape2D for gatherable resources
- **LocationMarkers**: Marker2D nodes for points of interest

### Domain Scenes
Created four new domain scenes:
- `game/scenes/domains/mortal_plains.tscn` — Mortal tier, iron ore and herb resources, beast zones
- `game/scenes/domains/spirit_peaks.tscn` — Spirit tier, spirit stone and jade ore resources, spirit beast zones
- `game/scenes/domains/immortal_court.tscn` — Immortal tier, immortal essence and star metal resources, elemental zones
- `game/scenes/domains/transcendent_realm.tscn` — Transcendent tier, dao fragment and void crystal resources, primordial zones

## How Each Criterion Is Now Met

| Criterion | Status | Evidence |
|-----------|--------|----------|
| 1. Proper root structure | Met | All scenes have Node2D root with `world_entry.gd` script |
| 2. Spawn points | Met | All scenes have `SpawnPoint` Marker2D + `NPCSpawnPoints` group |
| 3. Location markers | Met | All scenes have `LocationMarkers` group with POI Marker2D nodes |
| 4. Resource nodes | Met | All scenes have `ResourceNodes` group with Area2D + CollisionShape2D |
| 5. Enemy spawn zones | Met | All scenes have `EnemySpawnZones` group with Area2D + CollisionShape2D |
| 6. Navigation | Met | All scenes have NavigationRegion2D node |
| 7. Visual representation | Met | All scenes have ColorRect ground with tier-appropriate color |
| 8. Tier-specific content | Met | Each tier has unique ground color, resource names, zone names, and POI names |
| 9. Entry/exit points | Met | All scenes have `EntryPoints` and `ExitPoints` groups with Marker2D nodes |
| 10. Loadable | Met | All scenes use valid Godot 4.7 .tscn format with proper ext_resource and sub_resource |

## What Gaps Remain

- **NavigationPolygon**: NavigationRegion2D nodes exist but have no NavigationPolygon assigned. Pathfinding will not work until polygons are baked or assigned in the editor.
- **Resource interaction logic**: `interact_with_resource()` returns a dictionary but does not yet integrate with the items/inventory module. Wiring to actual item collection is future work.
- **Enemy spawning logic**: `spawn_enemy()` and `random_enemy_spawn_position()` provide positions but do not yet instantiate enemy actors. Integration with a combat/encounter system is future work.
- **NPC spawning logic**: `spawn_npc()` provides positions but does not yet instantiate NPC actors. Integration with a dialogue or faction system is future work.
- **Scene transitions**: Entry/exit points are marked but do not yet trigger scene changes. Integration with a scene manager is future work.
- **Visual polish**: Ground is a flat ColorRect. Future work includes tilemaps, sprites, and decorative elements.
- **Tests**: No GDScript tests for the new world_entry.gd methods. Contract tests should be added under `game/tests/app/`.
