# World Map UI

## CanvasLayer Structure

- World map is a `CanvasLayer` overlay on top of the current gameplay scene
- Layer 10+ to sit above world content but below modal UI
- Contains a full-rect `ColorRect` dim background + a `Control` root for map content
- Toggle visibility; never destroy — reuse across teleports

## Node Graph Data Model

- Nodes = locations (cities, sects, domains, dungeons)
- Edges = connections (travel routes, portals, ascension paths)
- Data-driven: `WorldLocationDef` resources define nodes; edges derived from `tier` + `faction_id`
- Each node: `location_id`, `display_name`, `tier`, `faction_id`, `danger_level`
- Each edge: `from_id`, `to_id`, `travel_type` (walk/portal/ascension)

## Click-to-Teleport Flow

1. Player clicks a node `Button` on the map
2. Screen emits `location_selected(location_id)` signal
3. `app/` receives signal, calls `change_scene_to_file(target_scene)`
4. Target scene loads; player spawns at designated spawn point
5. World map hides during transition, reappears on return

## Visual Design

- Nodes: circular `TextureButton` with faction-colored border
  - Qi Dao — Azure (`Color(0.3, 0.6, 0.9)`)
  - Body Dao — Gold (`Color(0.9, 0.7, 0.2)`)
  - Mind Dao — Violet (`Color(0.7, 0.4, 0.9)`)
- Edges: `Line2D` with `width=2`, color matches source faction
- Current location: highlighted with `focus_ring` style
- Locked nodes (tier not reached): grayed out, `disabled=true`
- Labels: `Label` below each node, `MetaLabel` theme variation

## Integration with ScreenStack

- World map is NOT a `ScreenStack` screen — it is a `CanvasLayer` overlay
- Screens push/pop on the stack; world map floats above all screens
- `ScreenStack` input is paused while world map is visible
- World map reads `WorldApi` facade for current location + available destinations
- No autoload holds world map UI — it is owned by `app/` composition root

## Screen Contract

- `summary() -> Dictionary` returns:
  - `current_location`: StringName
  - `available_destinations`: Array[Dictionary]
  - `nodes`: Array[Dictionary] (id, name, tier, faction, unlocked)
  - `edges`: Array[Dictionary] (from, to, type)
