# 0206 A domain minimap draws the payload it is handed

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0846

## Context

`DomainMinimap.render` (`domain_minimap.gd:59-73`) already publishes everything a
floor plan needs, and every value is a primitive: `bounds` `[x,y,w,h]`,
`rooms[] {room_id, kind, tags, rect[x,y,w,h], reachable, discovered, hostile, is_entry,
is_core, tier, tier_rank}`, `pois[] {room_id, tag, marker, anchor[x,y], tier}`,
`routes[] {from, to, points[[x,y]…], width}`, `zones[] {room_id, bounds, severity}`,
`discovered[]`, `layout{}`, `weather`. Layout is one rule for the whole repo —
`DomainPaths.layout` (`domain_paths.gd:185`), which ADR 0072 froze.

Nothing draws it. `domain_explore_model.gd:630-646` counts four integers off that
dictionary and calls it a floor plan, and `domain_explore.tscn:95-100` puts those counts
in a `Label`. The screen reads the payload whole (`domain_explore_model.gd:144`) but the
only shape that reaches a player is text.

`MapGraph` (`map_graph.gd:1-58`) is the one drawing `Control` in `ui/`, and it draws
directed *edges* between *node positions the caller already placed*. The domain needs
filled rooms, corridors, a marker set and a player position — none of which is a node
graph, and none of which `MapGraph` has a parameter for. Reusing it means growing it into
a shape library with two data models inside it.

## Decision

**A domain-specific `DomainMapView` (Control) draws the payload, sized from `bounds` into
an aspect-fitted inner rect. `MapGraph` is not extended — the world map's node-link model
and a floor plan are different pictures, and one `_draw` serving both would be the second
thing that can disagree with the map.**

- **Layers, back to front:** corridor polylines (`routes[].points`, stroked at `width`
  tiles) → room fills (`rooms[].rect`, inset one tile so corridors read) → room outlines →
  severe zones (`zones[].bounds`, hatched by `severity`) → POI markers → the player's room.
  Each layer reads one payload key and nothing else.
- **Scale is `min(inner.w / bounds.w, inner.h / bounds.h)`, then centre.** Floor-clamped
  at `MIN_TILE_PX` so a large map zooms out to a legible blob rather than sub-pixel
  hairlines; the node reports the factor it used so `summary()` can publish it.
- **The node holds no geometry of its own.** No re-layout, no tier derivation, no
  "distance from entry" colouring — ADR 0073 forbids the last, ADR 0072 the first. A
  drawing disagreeing with `DomainPaths.layout` would be a second map.
- **The player marker sits in the room the actor is in, not at a tracked transform.**
  `DomainApi` publishes no intra-room position yet.

### Reconciling the UI standard

The standard forbids absolute positions and requires anchors + containers. Both hold:

- **Layout stays anchored.** `DomainMapView` is an `AspectRatioContainer`'s child in
  `domain_explore.tscn`'s `MapPanel`, so its position is a container result, never a
  constant; its own `resized` signal recomputes the scale, the path
  `world_map_screen.gd:164-169` already uses for `MapArea`.
- **A `_draw` call computes *pixels*, not layout.** The prohibition exists so a widget
  cannot sit at a hard-coded spot and break on resize. A routine that maps tile
  coordinates to pixels by a factor derived from its own `size` has no hard-coded
  position at all. `MapGraph` is the existing precedent (ADR 0048).

`DomainMapView` is a **widget, not a screen**: `ui/panels/`, `class_name`, one
`show_map(payload) -> void` door (the `NpcRosterPanel.show_room` shape,
`npc_roster_panel.gd:87`), never built in `_ready()`, `.tscn` instanced like any panel.

## Consequences

- BL-0846 closes when `MapLabel`'s four counts are replaced by this panel; the counts stay
  in `summary()` as `*_count` primitives, so existing headless assertions keep working.
- Colours, glyphs and hatch density are named constants in the node. No
  `theme_override_*`, per the standard.
- `zones` are drawn unfogged because `_zones` is unfogged
  (`domain_minimap.gd:179-182`) and ADR 0170 relies on it.
- **Trade-off rejected:** rooms as themed `Panel` children so containers lay them out —
  no container lays out overlapping free rectangles, and it costs N `Control` nodes per
  room, the per-refresh churn INC-0002/INC-0041 warn about.
- **What would change my mind:** `MapGraph` growing a fill/marker API for the world map
  too, which would make the two pictures one vocabulary.

## `summary()`

Primitives only, nested under the screen's `minimap_view` key (`summary()` →
`Dictionary`):

```
{"bound": true, "wires": 3, "rooms": 5, "corridors": 4, "markers": 2,
 "zones": 1, "player_room": "east_gate", "scale": 0.0625,
 "tile_px": 4.0, "bounds": [x,y,w,h], "clipped": false}
```

`bound: false` is the empty vocabulary — no panel wired reads as the honest nothing, not
a blank map. Every number is a count of what the node painted, or `0`; no `Color`, no
`Rect2`, no `Vector2`.