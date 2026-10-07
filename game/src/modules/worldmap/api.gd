class_name WorldmapApi
extends RefCounted

## Public facade for the `worldmap` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

## One shared graph per process: places and their edges change rarely and are
## read by every query, so rebuilding one per call would be all cost and no
## freshness. Tests reset it through `clear_graph`.
static var _graph: WorldmapGraph = WorldmapGraph.new()


## Forget every node and edge. Tests only: production graphs are built once.
static func clear_graph() -> void:
	_graph = WorldmapGraph.new()


## Register places and their travel edges. Returns `{ok, reason, nodes, edges}`
## naming the first refusal, so a half-built graph never reads as whole.
static func build_graph(nodes: Array, edges: Array) -> Dictionary:
	var built_nodes := 0
	for entry in nodes:
		var outcome := _graph.add_node(entry as Dictionary)
		if not bool(outcome.get("ok", false)):
			return {
				"ok": false,
				"reason": String(outcome.get("reason", "")),
				"nodes": built_nodes,
				"edges": 0,
			}
		built_nodes += 1
	var built_edges := 0
	for entry in edges:
		var outcome := _graph.add_edge(entry as Dictionary)
		if not bool(outcome.get("ok", false)):
			return {
				"ok": false,
				"reason": String(outcome.get("reason", "")),
				"nodes": built_nodes,
				"edges": built_edges,
			}
		built_edges += 1
	return {"ok": true, "reason": "", "nodes": built_nodes, "edges": built_edges}


## Places contained in `node_id` — containment only, never travel.
static func children_of(node_id: String) -> Array:
	return _graph.children_of(node_id)


## Travel edges leaving `node_id`.
static func edges_from(node_id: String) -> Array:
	return _graph.edges_from(node_id)


## Every node reachable from `node_id` over travel edges.
static func reachable(node_id: String) -> Array:
	return _graph.reachable(node_id)


## The node, or `{}` when no such place exists.
static func node(node_id: String) -> Dictionary:
	return _graph.node(node_id)


## Generate one chunk through the standard pass set. Pure data: no nodes,
## no scenes, reproducible from the same inputs.
static func generate_chunk(
	node_id: String,
	cx: int,
	cy: int,
	chunk_size: int,
	seed: int,
	config: Dictionary,
	mutations: Dictionary = {}
) -> WorldChunk:
	var generator := WorldmapApi.default_generator()
	return generator.generate(node_id, cx, cy, chunk_size, seed, config, mutations)


## The standard pass set: terrain, water, scatter, collision, in dependency
## order. One place, so every caller generates the same layers.
static func default_generator() -> WorldmapGenerator:
	var generator := WorldmapGenerator.new()
	generator.register_pass(WorldmapTerrainPass.new())
	generator.register_pass(WorldmapWaterPass.new())
	generator.register_pass(WorldmapScatterPass.new())
	generator.register_pass(WorldmapCollisionPass.new())
	return generator
