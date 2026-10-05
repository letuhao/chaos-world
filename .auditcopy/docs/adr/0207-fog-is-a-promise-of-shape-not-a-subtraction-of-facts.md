# 0207 Fog is a promise of shape, not a subtraction of facts

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0846 (the fog half)
- Builds on: ADR 0206

## Context

`DomainMinimap` fogs by **subtraction**: `_discovered_ids` (`domain_minimap.gd:101-106`)
keeps only discovered rooms, and the file's own header (`:19-21`) says an unvisited room
is "not drawn: not faded, not greyed, not drawn — because an unvisited room shown dimly is
the spoiler the fog exists to prevent."

ADR 0072 guarantees every room is reachable from the entry, and ADR 0170 records the
corridor graph symmetric and mutually confirmed (`domain_paths.gd:352-357`). So at first
visit the map is one room in an empty frame. A player sees a single box and is told
`3 markers` — a number about somewhere they cannot see. **Fog that only removes things
converts the map from a planning instrument into a post-mortem**: it rewards a player who
has already been everywhere and tells an arriving player nothing about whether there is
anywhere to go.

The genre answer is consistent across crawlers, roguelikes and tactical maps: fog never
subtracts the *shape* of the unknown, it withholds the *contents*. The known extent is
legible from the start — a player knows a dungeon has rooms without knowing what is in
them — the frontier is drawn as a seam, and what a room *promises* is withheld per marker
rather than per room.

## Decision

**Fog partitions the payload into three bands, and only one of them is empty. The unknown
is drawn as a shape with no label; it is never drawn as nothing.**

- **Remembered — full detail.** Discovered rooms: fill, outline, POI markers, population,
  hazards. `_discovered_ids` unchanged.
- **Frontier — outline only.** Every room one corridor away from a discovered room: a dim
  outline, no fill, no marker, no name, no tier. The seam IS the information — "three
  ways on, none taken". Reachability comes from `DomainMap.reachable_room_ids()`, already
  in the payload (`domain_minimap.gd:120`), so this adds no module surface. **Capped at
  `MAX_FRONTIER_ROOMS` (8), reporting `frontier_truncated`**, because a wide room graph
  would otherwise draw a wall of outlines hiding the remembered rooms behind it — and a
  bounded number is a summary field, not a loop.
- **Hidden — nothing, and never a lie.** Beyond the frontier: not drawn.

**Two bands are deliberately NOT fogged**, both because the module already published them
unfogged and an accepted ADR depends on it:

- **`zones`** — `_zones` is unfogged by design (`domain_minimap.gd:179-182`) and ADR 0170
  (`:37`) locks it: "a hazard must be visible before you stand in it".
- **The room count and `bounds`** — from the drawn rects and the authored room list, not
  the discovered set. The player always knows the size of the thing they are in.

### The affordance

The decision a player makes is **"which of these outlines do I spend a step on?"** — only
a decision if the outlines differ. They do, by three things fog never withholds:

1. **Corridor count** — the doors between rooms, visible on the seam, are the cost. Two
   doors is a detour; one is the shortest way in.
2. **Adjacency to remembered rooms** — an outline touching three remembered rooms is the
   middle of the map, not an edge of it.
3. **Shape** — an outline's `rect` says corridor from chamber, and `kind` gates mouth
   width (`WIDE_MOUTH_KINDS`, `domain_paths.gd:78`), which the polylines already reflect.

**The player position is drawn on the remembered band only.** "You are here" is the one
thing fog must never qualify — a player who cannot locate themselves has no frame for any
of the above.

## Consequences

- `frontier` / `frontier_truncated` are **presentation, not module state**: computed in
  `ui/panels/` from `rooms[]`, `layout{}` and `routes[]` already in the payload. **The
  module's `discovered` set stays authoritative for what is remembered** — ADR 0206's
  "the drawing holds no geometry of its own" holds, because a frontier room's `rect` is
  read, never invented.
- **Do NOT widen `DomainMinimap` to emit a frontier.** That makes a presentation choice a
  module fact, and a frontier is about rooms the player has *not* stood in, drawn without
  standing in them — the line ADR 0073's one-source tags discipline protects.
- **Trade-off rejected:** showing a frontier room's `tier`, making the map a full route
  planner — it turns exploration into optimisation, and the player stops choosing which
  way to go and starts walking a solved path.
- **Trade-off rejected:** filling the hidden band as a flat "unknown mass" over `bounds`.
  Busy without legible, and it over-promises: a filled block reads as solid, not unvisited.
- **What would change my mind:** a second consumer of the payload needing the frontier as
  data (the headless domain driver, once it simulates a walk), which would justify
  publishing it from the module instead.

### `summary()`

Adds to ADR 0206's dictionary, primitives only: `frontier: int`,
`frontier_truncated: bool`, `hidden_rooms: int` (authored rooms − remembered − frontier;
the number fog withheld, published so a test can assert the partition is total and
nothing is silently dropped).