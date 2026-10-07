class_name WorldmapApi
extends RefCounted

## Public facade for the `worldmap` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

## One shared graph per process: places and their edges change rarely and are
## read by every query, so rebuilding one per call would be all cost and no
## freshness. Tests reset it through `clear_graph`.
static var _graph: WorldmapGraph = WorldmapGraph.new()

## The domain seam: who enters and leaves real runs. Installed by `app/`
## (the composition root owns the actor a run is written onto). Tests reset
## through `clear_domain`.
static var _domain_entry: Callable = Callable()
static var _domain_exit: Callable = Callable()


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


## Whether an edge may be crossed under `context`. No hook passes; a hook
## asks its installed evaluator; an unwired hook refuses by name (see
## `WorldmapGates`). The one verb a scene asks before traveling.
static func can_traverse(edge: Dictionary, context: Dictionary = {}) -> Dictionary:
	return WorldmapGates.evaluate(edge, context)


## Install the run entry and exit (statics beside `_graph` above). Refuses a
## dead Callable by name; re-installing replaces, so a boot re-mount never stacks.
static func install_domain(entry: Callable, exit: Callable) -> Dictionary:
	if not entry.is_valid() or not exit.is_valid():
		return {"ok": false, "reason": "dead_domain_seam"}
	_domain_entry = entry
	_domain_exit = exit
	return {"ok": true, "reason": ""}


## Forget the seam. Tests only: production installs once at boot.
static func clear_domain() -> void:
	_domain_entry = Callable()
	_domain_exit = Callable()


## Whether a domain seam is installed.
static func has_domain() -> bool:
	return _domain_entry.is_valid() and _domain_exit.is_valid()


## Enter the run for `template_id`. No seam refuses by name; a seam's own
## refusal passes through untouched, because only the run owner knows why.
static func enter_domain_run(template_id: String, seed: int) -> Dictionary:
	if not has_domain():
		return {"ok": false, "reason": "no_domain_seam"}
	return _domain_entry.call(template_id, seed) as Dictionary


## Leave the current run. Same contract as entry.
static func leave_domain_run() -> Dictionary:
	if not has_domain():
		return {"ok": false, "reason": "no_domain_seam"}
	return _domain_exit.call() as Dictionary


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
