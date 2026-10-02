# World Map Screen Audit

## Does the WorldMapScreen correctly display locations?

**Yes.** The screen reads from `WorldApi.locations()` which loads all `WorldLocationDef` resources from `res://data/world/locations/`. Each location is rendered as a `Button` in a `VBoxContainer` (`NodeLayer`). The `MapGraph` control draws edges between consecutive buttons in `_draw()`.

## Does the WorldApi facade expose all needed methods?

**Yes.** The facade now exposes:
- `locations(actor)` — returns all world locations as primitive dictionaries
- `summary(actor)` — returns world state (tier, size, stability, etc.)
- All existing methods (tier, stability, laws, inhabitants, resources, create_world, expand_world, add_law, add_inhabitant, pay_upkeep)

The facade is at 12 methods (the cap). `preview_expand` was removed (it was unused).

## Is the app integration correct?

**Yes.** `Main._ready()`:
1. Builds the actor
2. Initializes the world module (`WorldApi.create_world(actor, &"micro", 10.0)`)
3. Connects to `BodyCultivationPanel.world_map_requested`
4. Pushes `WorldMapScreen` onto the stack when the signal fires

## Are there any missing integration points?

- **Location click handling**: `WorldMapScreen` emits `location_selected` but nothing connects to it yet. This is expected — the screen is a pure consumer and the composition root will wire up actions when gameplay needs them.
- **Current location tracking**: The screen highlights the first location as "current". A future enhancement could track the actor's actual location.

## Are there any edge cases not covered?

- **Empty locations**: If no `.tres` files exist, `locations()` returns `[]` and the screen shows an empty graph. This is handled gracefully.
- **Null actor**: `WorldApi.locations(null)` returns all locations (location data is static content, not actor-dependent). The screen returns `{}` from `_summary()` when actor is null.
- **Scene missing nodes**: `_bind_nodes()` uses `get_node_or_null` and the screen handles null containers gracefully.

## Files changed

- `game/src/modules/world/api.gd` — replaced `preview_expand` with `locations()`
- `game/src/ui/screens/world_map_screen.gd` — rewrote to use `WorldApi.locations()`
- `game/src/ui/screens/world_map_screen.tscn` — updated scene structure (MapContainer + NodeLayer)
- `game/src/ui/screens/map_graph.gd` — new file, draws edges between location buttons
- `game/src/ui/screens/body_cultivation_panel.gd` — added `world_map_requested` signal and `act_world_map()`
- `game/src/ui/screens/body_cultivation_panel.tscn` — added WorldMapButton
- `game/src/app/main.gd` — wired in world module, handle world map navigation
- `docs/adr/0048-world-map-screen.md` — ADR for the decision
