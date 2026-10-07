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

## The transition seam for non-seamless arrivals (a loading screen, a fade).
## Installed by `app/`; tests reset through `clear_transition`.
static var _transition: Callable = Callable()

## Descent return cells, outermost first. Owned HERE rather than by any scene:
## navigating away frees the scene, and a return recorded on a freed node is
## a way back that no longer exists. Non-empty means inside a domain node.
## Tests reset through `clear_returns`; a domain-route Leave that bypasses
## the scene orphans the top entry, and the next descent stacks above it —
## LIFO still returns the newest first, so the orphan costs nothing.
static var _returns: Array = []


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


## The loot-band seam: who enters and abandons boss bands. Installed by `app/`
## (the composition root owns the actor a band is written onto), read by the
## scene when a node config names a `loot_domain`. Same shape as the domain
## seam; a different question, so a different pair. Tests reset through
## `clear_loot`.
static var _loot_entry: Callable = Callable()
static var _loot_exit: Callable = Callable()


## Install the band entry and exit. Refuses a dead Callable by name;
## re-installing replaces, so a boot re-mount never stacks.
static func install_loot(entry: Callable, exit: Callable) -> Dictionary:
	if not entry.is_valid() or not exit.is_valid():
		return {"ok": false, "reason": "dead_loot_seam"}
	_loot_entry = entry
	_loot_exit = exit
	return {"ok": true, "reason": ""}


## Forget the seam. Tests only: production installs once at boot.
static func clear_loot() -> void:
	_loot_entry = Callable()
	_loot_exit = Callable()


## Whether a loot seam is installed.
static func has_loot() -> bool:
	return _loot_entry.is_valid() and _loot_exit.is_valid()


## Enter the band for `domain_id` at `tier` with `seed`. No seam refuses by
## name; a seam's own refusal passes through untouched.
static func enter_loot_band(domain_id: String, tier: int, seed: int) -> Dictionary:
	if not has_loot():
		return {"ok": false, "reason": "no_loot_seam"}
	return _loot_entry.call(domain_id, tier, seed) as Dictionary


## Abandon the current band. Unclaimed rewards are kept by the module, so
## walking out never loses what fell. Same contract as entry.
static func leave_loot_band() -> Dictionary:
	if not has_loot():
		return {"ok": false, "reason": "no_loot_seam"}
	return _loot_exit.call() as Dictionary


## Remember where a descent left from. The scene pushes once the run exists.
## (Statics live beside `_graph` above.)
## `band` records whether a loot band was entered for this descent, so the
## return knows whether there is a band to abandon.
static func push_return(node_id: String, cell: Vector2i, band: bool = false) -> void:
	_returns.append({"node": node_id, "cell": cell, "band": band})


## Take the newest return, or `{}` when above ground.
static func pop_return() -> Dictionary:
	if _returns.is_empty():
		return {}
	return _returns.pop_back() as Dictionary


## Read the newest return without taking it, or `{}` when above ground.
static func peek_return() -> Dictionary:
	if _returns.is_empty():
		return {}
	return (_returns[_returns.size() - 1] as Dictionary).duplicate(true)


## How many descents deep the player stands.
static func return_depth() -> int:
	return _returns.size()


## Forget every return. Tests only.
static func clear_returns() -> void:
	_returns.clear()


## Install the transition hook for non-seamless arrivals (statics beside
## `_graph` above). A node config with `seamless: false` yields control to
## the hook before the scene switches; the hook answers `{ok, reason}` and a
## refusal holds the player where they stand. Refuses a dead Callable by name.
static func install_transition(hook: Callable) -> Dictionary:
	if not hook.is_valid():
		return {"ok": false, "reason": "dead_transition_seam"}
	_transition = hook
	return {"ok": true, "reason": ""}


## Forget the hook. Tests only.
static func clear_transition() -> void:
	_transition = Callable()


## Whether a transition hook is installed.
static func has_transition() -> bool:
	return _transition.is_valid()


## Run the transition for an arrival both sides named. No hook refuses by
## name; a hook's own refusal passes through untouched.
static func run_transition(from_node: String, to_node: String, edge: Dictionary) -> Dictionary:
	if not has_transition():
		return {"ok": false, "reason": "no_transition_seam"}
	return _transition.call(from_node, to_node, (edge as Dictionary).duplicate(true)) as Dictionary


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


## The standard pass set, in dependency order. One place, so every caller
## generates the same layers.
static func default_generator() -> WorldmapGenerator:
	var generator := WorldmapGenerator.new()
	generator.register_pass(WorldmapTerrainPass.new())
	generator.register_pass(WorldmapWaterPass.new())
	generator.register_pass(WorldmapElevationPass.new())
	generator.register_pass(WorldmapScatterPass.new())
	generator.register_pass(WorldmapResourcesPass.new())
	generator.register_pass(WorldmapStructuresPass.new())
	generator.register_pass(WorldmapLandmarksPass.new())
	generator.register_pass(WorldmapRoadsPass.new())
	generator.register_pass(WorldmapEncountersPass.new())
	generator.register_pass(WorldmapNpcsPass.new())
	generator.register_pass(WorldmapCollisionPass.new())
	generator.register_pass(WorldmapNavigationPass.new())
	generator.register_pass(WorldmapMetadataPass.new())
	return generator
