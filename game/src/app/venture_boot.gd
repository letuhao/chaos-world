class_name VentureBoot
extends RefCounted

## Composition-side host for the venture route: the demo graph, its configs,
## and the verbs a screen reaches only as Callables.
##
## ## Why the screen never names this file's types
##
## `ui/` may not name `app/` (a private unit) nor any worldmap type except
## through the module facade — and the scene itself is not the facade. So the
## screen holds Callables and plain `Node` handles, and every verb below takes
## the screen as its first argument. The one exception is the return values:
## plain Dictionaries of primitives, never the scene.
##
## ## Why nothing here is remembered
##
## No member, no static: the scene is found by name under the screen that
## shows it (`WORLD_NODE` below), the graph and configs are rebuilt per call
## from constants, and freeing the screen frees the world with it. A second
## reference would be a second thing that can outlive the visit.
##
## The demo is the same three nodes the headless streaming suite walks, so a
## green suite and a played session describe one place: an overworld with a
## doorway into a nested authored cave and a portal to a differently-sized
## far universe.

const WORLD_NODE := "VentureWorld"
const HOLDER_NAME := "WorldHolder"

const NODES: Array[String] = ["overworld", "cave", "far"]
const ENV := "mortal_greenwood"


## Open `node_id` under the screen's holder, freeing whatever stood there.
## Refuses an unknown node by name; a half-opened node is reported, never shown.
static func open(screen: Control, node_id: String) -> Dictionary:
	if screen == null:
		return {"ok": false, "reason": "no_surface"}
	if not NODES.has(node_id):
		return {"ok": false, "reason": "unknown_node", "node": node_id}
	var holder := screen.get_node_or_null("%" + HOLDER_NAME)
	if holder == null:
		return {"ok": false, "reason": "no_surface"}
	close(screen)
	var graph := _demo_graph()
	var configs := _demo_configs()
	var scene := WorldmapScene.new()
	scene.name = WORLD_NODE
	holder.add_child(scene)
	var outcome := scene.open(graph, node_id, configs)
	if not bool(outcome.get("ok", false)):
		scene.free()
		return outcome
	return {"ok": true, "reason": "", "node": node_id}


## Free the world under the screen. Idempotent: closing nothing reports
## `{"ok": true, "freed": 0}` rather than failing a teardown that calls twice.
static func close(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": true, "reason": "", "freed": 0}
	scene.free()
	return {"ok": true, "reason": "", "freed": 1}


## Step the player one cell. Unopened reads as refused, not as a crash.
static func step(screen: Control, dx: int, dy: int) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"moved": false, "traveled": false, "reason": "unopened"}
	return scene.step(dx, dy)


## Destroy whatever the player's cell masks. Unopened refuses by the same name.
static func destroy(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened", "freed": 0}
	return scene.destroy_at(scene.player_cell())


## The venture read model, primitives only: demo nodes, open state, and the
## live world's own debug summary with edges trimmed to strings. `{}`
## answers nothing: an unopened screen reports its nodes and `open: false`.
static func read(screen: Control) -> Dictionary:
	var view := {"nodes": NODES.duplicate(), "open": false}
	var scene := _scene_of(screen)
	if scene == null:
		return view
	view["open"] = true
	var summary := scene.debug_summary()
	view["node"] = String(summary.get("node", ""))
	view["player_cell"] = (summary.get("player_cell", [0, 0]) as Array).duplicate()
	view["holders"] = (summary.get("holders", []) as Array).duplicate()
	var edges: Array = []
	for edge in summary.get("edges", []) as Array:
		edges.append(
			{
				"to": String((edge as Dictionary).get("to", "")),
				"kind": String((edge as Dictionary).get("kind", ""))
			}
		)
	view["edges"] = edges
	view["loaded"] = (
		((summary.get("streamer", {}) as Dictionary).get("loaded", []) as Array).duplicate()
	)
	return view


static func _scene_of(screen: Control) -> WorldmapScene:
	if screen == null:
		return null
	var holder := screen.get_node_or_null("%" + HOLDER_NAME)
	if holder == null:
		return null
	return holder.get_node_or_null(NodePath(WORLD_NODE)) as WorldmapScene


## The demo graph. Rebuilt per call from constants: places change rarely and
## are read by every verb, and a shared graph would be shared mutable state.
static func _demo_graph() -> WorldmapGraph:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	graph.add_node({"id": "far", "kind": &"universe", "parent": ""})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "cave",
				"kind": &"doorway",
				"from_cell": Vector2i(3, 1),
				"to_cell": Vector2i(1, 1),
			}
		)
	)
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "far",
				"kind": &"portal",
				"from_cell": Vector2i(5, 5),
				"to_cell": Vector2i(2, 1),
			}
		)
	)
	return graph


static func _demo_configs() -> Dictionary:
	return {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 1234,
			"entry_row": 1,
			"data_radius": 2,
			"scene_radius": 1,
			"scatter":
			[
				{"archetype": "flora.shrub", "density": 0.05, "blocking": true},
				{"archetype": "flora.flower_cluster", "density": 0.08, "blocking": false},
			],
		},
		"cave":
		{
			"environment": ENV,
			"chunk_size": 6,
			"seed": 99,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"water": false,
			"authored_terrain": _flat_ground(6),
			"scatter":
			[
				{"archetype": "stone_and_ore.small_rock", "density": 0.3, "blocking": true},
			],
		},
		"far":
		{
			"environment": ENV,
			"chunk_size": 12,
			"seed": 7,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter": [],
		},
	}


static func _flat_ground(size: int) -> Array:
	var rows: Array = []
	for _y in size:
		var row: Array = []
		for _x in size:
			row.append("ground_tile.base_ground")
		rows.append(row)
	return rows
