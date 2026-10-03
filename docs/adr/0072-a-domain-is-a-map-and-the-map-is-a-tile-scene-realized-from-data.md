# 0072 A domain is a map, and the map is a tile scene realized from data

- Status: Accepted
- Date: 2026-10-03

## Context

`DomainDef` (`game/src/modules/world/domain_def.gd:6-8`) is three exported fields — `id`, `display_name`, `boss_ids` — across 160 authored `.tres`. `LootApi.enter_domain` (`game/src/modules/loot/api.gd:61-85`) mutates `actor.module_data["loot_state"]`: no scene is loaded, no node created, no position touched. A domain today is a loot-table bookkeeping function wearing a spatial name.

Measured absence across `game/src`: zero `TileMap`, zero `AStar`, zero `NavigationAgent`, zero `NavigationRegion` in GDScript. The only `Vector2i` is `WorldEntry.realm_range()`. Eight authored scenes (`game/scenes/domains/*.tscn`, `game/scenes/worlds/*.tscn`) are loaded by nothing — `res://scenes/domains/` has zero references repo-wide — and their names correspond to no `DomainDef` id.

`Actor` is already the universal entity: `RefCounted`, one shape, four construction sites, all player or offspring. That premise is structurally free. What is missing is a map, and anything to put in it.

The fork: a domain as pure simulation over `RefCounted`, or a walkable tile scene. **Decided: a tile scene.** A domain you cannot walk is a spreadsheet. The simulation discipline survives anyway, because the scene is *realized from* data rather than being the data — and because the headless suite drives it (ADR 0043) and screenshots are captured for visual verification.

## Decision

**One `DomainMap` (RefCounted) is the single description of a domain's shape; one `DomainScene` (Node2D + TileMapLayer) realizes it for play.** The scene is a *view*, never the source of truth — no gameplay rule reads a node.

- `DomainMap` = `{rooms, corridors, spawn_refs, fixtures, environment, seed}`. Engine-agnostic, JSON-round-trippable, no `Node` and no `TileMap` reference. ADR 0001/0003 keep `Actor` engine-free; the map keeps the same discipline so it is testable without a scene tree.
- `DomainScene` builds floor and wall `TileMapLayer`s from `DomainMap`, places `Marker2D` spawn points, converts every `EnvironmentZoneDef` into an `Area2D`, and bakes a `NavigationRegion2D` from the corridor graph. It holds no rules and derives nothing gameplay reads.
- **`DomainDef.layout` is one discriminated field**: either `scene_id` (handcrafted — the authored `.tscn` is the map) or `template_id` + `seed` (generated). Both produce the same `DomainMap`, so nothing downstream can tell which it got. A def with neither keeps today's behaviour exactly.
- **Every new `DomainDef` field is optional.** All 160 authored `.tres` stay valid and audit-clean; migration is not a prerequisite for any stage.
- **Navigability is a property of the map, not the scene.** Every room is reachable from the entry under the corridor graph. A generator must produce a connected map or fail loudly — a bounded, small guard naming the failure, never an unbounded retry (AGENTS.md's log-hazard rule).
- **Determinism is the seed's whole job.** `seed` derives every stream from an injected `RandomNumberGenerator`; the same seed yields a byte-identical `DomainMap`, a different seed does not.
- **Walkability is verified by a headless driver, not by eye.** `tools` gains a domain driver that enters a domain, prints map and encounter state as JSON, accepts `--cmd` verbs, and writes a screenshot per step. Same contract the UI already honours (`summary()` primitives), applied to a map.

## Consequences

- One domain shape serves both producers; handcrafted and generated are the same object downstream (BL-0211, BL-0212, BL-0215).
- The map is testable without a display, so AC1/AC3/AC6 are unit tests, and AC5/AC7 need the driver (BL-0220).
- **Deliberately not decided here:** the fate of the 8 orphan scenes and of `world_entry.gd` (BL-0213, BL-0214). Both are recorded rather than silently absorbed, because `test_arch_rules.gd:473-483` freezes `world_entry.gd`'s source and reviving it is a real edit to a pinned shape.
- The tile layer is a *rendering* commitment, deliberately the one place the design touches the engine: a data-defined map that a scene realizes is not the same as a data-defined map that a scene *is*.
