# 0073 A handcrafted domain and a generated domain assemble the same room kit

- Status: Accepted
- Date: 2026-10-03

## Context

The requirement is explicit: a domain is *either* handcrafted *or* generated from a template, and the two must **share resources**. Handcrafting one room kit and procedurally generating a second is the standard failure — two art sets, two spawn conventions, two sets of bugs, and a player who notices which one they are in.

The repo already holds the right instinct in the wrong place. `WorldLocationDef` (`game/src/modules/world/world_location_def.gd`) is the only authored def that carries environment, and `game/scenes/domains/*.tscn` are four authored scenes with no generator counterpart and no id join to any `DomainDef` (BL-0213).

## Decision

**`RoomDef` is the shared currency. A room is a room whether a human placed it or a template chose it.**

- A `RoomDef` carries: `room_id`, `kind` (floor, corridor, chamber, settlement, arena, gate, core), `size`, `tags`, `actor_spawn_refs`, `fixtures`, `environment_zones`, `exits`. Tags drive encounter roster, hazard placement, treasure weighting and the minimap POI layer **from one source** — never a post-hoc heuristic.
- A **handcrafted** domain is a scene whose rooms are authored `RoomDef`s. A **generated** domain is a template that *assembles the same authored `RoomDef`s`* into a graph. The generator picks and places; it does not invent room content.
- **Generation supplies the graph, not the art.** BSP or graph-grammar for the node graph and corridors; handcrafted rooms dropped in as leaves. This is the hybrid that suits a top-down 2D action RPG: authored sightlines and readable arenas matter more than organic cave realism.
- **Both producers emit the same `DomainMap` (ADR 0072) and pass the same contract test**: ≥1 room, ≥1 exit, every room reachable from entry, no orphan room, every `exits` target resolving. One suite, two producers — parity is asserted, not asserted-by-comment.
- **Parity is checked structurally**: a `DomainMap.to_dict()` from a handcrafted map and from a seeded generated map both validate against the same validator, and a room ref present in one and absent in the other is a bug.
- **A settlement room is a room kind, not a system.** A sect, a castle, or an inner world is a template whose rooms are `kind = settlement` — so the "inner world" and "sect inside a domain" requirements are one concept, not two.

## Consequences

- Handcrafted and generated content share one kit, one spawn convention, one audit rule (BL-0215).
- The inner-world / sect-inside-a-domain requirement lands as a room kind rather than a parallel system (BL-0219). **Note a real collision to resolve, not absorbed here:** `InsideWorld` and `WorldState` already exist in `core/` for the actor's personal inner world, and `inside_world_qi_density` is a live stat provider — whether a walkable inner world replaces, wraps, or maps over that state is an open decision.
- A generator that emits a room the kit does not contain is a **hard authoring error**, not a fallback: it fails loudly instead of substituting a default room (AGENTS.md — a feature that cannot work must fail out loud, not spin).
- The 8 orphan scenes' fate is still open (BL-0213) — this ADR decides the kit, not which scenes join it.
