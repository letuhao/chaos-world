# ADR 0048: World Map Screen

## Context

The world map screen read from `WorldApi.summary()` which does not return `nodes` or `edges`, so the map displayed no locations. The world module was not wired into the app composition root.

## Decision

- Added `WorldApi.locations()` — loads `WorldLocationDef` resources from `res://data/world/locations/` and returns them as primitive dictionaries. Replaced the unused `preview_expand()` to stay within the 12-method facade cap.
- Rewrote `WorldMapScreen` to read from `WorldApi.locations()` and render a clickable node graph with edges drawn by `MapGraph`.
- Added `MapGraph` — a `Control` subclass that draws edges between location buttons in `_draw()`.
- Wired the world module into `Main` — initializes a mortal-tier world on the actor and pushes `WorldMapScreen` when the body cultivation panel emits `world_map_requested`.
- Added a "World Map" button to `BodyCultivationPanel`.

## Consequences

- The world map displays all 4 locations as a vertical node graph with edges.
- The world module is initialized in the composition root.
- The facade stays at 12 methods (the cap).
