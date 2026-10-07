class_name WorldmapGenerator
extends RefCounted

## `seed -> context -> passes -> chunk`. Passes register by layer name and
## run in dependency order; an unsatisfied requirement fails the whole chunk
## loudly rather than generating on missing input. Deterministic end to end:
## the RNG is never rolled without a named stream, so the same
## (node, cx, cy, size, seed, config) answers the same chunk on every run.

var _passes: Dictionary = {}


## Register a pass. A duplicate layer is refused — two writers of one layer
## would make generation order the answer, which is not an answer.
func register_pass(stage: WorldmapContract) -> Dictionary:
	var layer := stage.pass_id()
	if layer == &"":
		return {"ok": false, "reason": "unnamed_pass"}
	if _passes.has(layer):
		return {"ok": false, "reason": "duplicate_layer", "layer": String(layer)}
	_passes[layer] = stage
	return {"ok": true, "reason": "", "layer": String(layer)}


## Registered layer names, sorted.
func layers() -> Array:
	var out := _passes.keys()
	out.sort()
	return out


## Generate one chunk. `config` carries `environment` and `scatter` (see the
## scatter pass); `mutations` reapplies a stored overlay afterwards, so a
## regenerated chunk keeps exactly what changed.
func generate(
	node_id: String,
	cx: int,
	cy: int,
	chunk_size: int,
	seed: int,
	config: Dictionary,
	mutations: Dictionary = {}
) -> WorldChunk:
	var order := _order()
	# The stream seed mixes the chunk coordinates in: without this, every
	# chunk of a node generates byte-identically (measured: chunks (0,0) and
	# (1,0) had the same walk pattern), and a world of copies is not a world.
	var stream_seed: int = (seed ^ (cx * 73856093) ^ (cy * 19349663)) & 0x7FFFFFFF
	var ctx := {
		"seed": stream_seed,
		"node": node_id,
		"cx": cx,
		"cy": cy,
		"size": chunk_size,
		"environment": String(config.get("environment", "")),
		"scatter": config.get("scatter", []),
		"authored_terrain": config.get("authored_terrain", []),
		"water": config.get("water", true),
		"palette": config.get("palette", ["ground_tile.base_ground"]),
		"roads": config.get("roads", 0),
		"resources": config.get("resources", []),
		"structures": config.get("structures", []),
		"settlements": config.get("settlements", []),
		"landmarks": config.get("landmarks", []),
		"landmark_density": config.get("landmark_density", 0.15),
		"encounter_tables": config.get("encounter_tables", []),
		"encounter_density": config.get("encounter_density", 0.0),
		"npc_roles": config.get("npc_roles", []),
	}
	var data := {"terrain": [], "props": [], "walkable": [], "layers": {}}
	# First-class fields stay three: a pass returns its layer top-level (e.g.
	# `{"elevation": rows}`) and anything beyond the three folds into `layers`
	# under the pass's own key, so a new pass never touches this function.
	# `props` is the one first-class exception: every scatter-family pass
	# APPENDS, because overwriting would let registration order eat writers.
	for layer in order:
		var stage := _passes[layer] as WorldmapContract
		var out := stage.run(ctx, data)
		for key in out.keys():
			if String(key) == "props" and out[key] is Array:
				(data["props"] as Array).append_array(out[key] as Array)
			elif String(key) in ["terrain", "walkable"]:
				data[key] = out[key]
			elif String(key) == "layers" and out[key] is Dictionary:
				for layer_key in (out[key] as Dictionary).keys():
					(data["layers"] as Dictionary)[layer_key] = (out[key] as Dictionary)[layer_key]
			else:
				(data["layers"] as Dictionary)[String(key)] = out[key]
	var chunk := WorldChunk.make("%s:%d,%d" % [node_id, cx, cy], node_id, cx, cy, chunk_size, seed)
	chunk.terrain = data.get("terrain", [])
	chunk.props = data.get("props", [])
	chunk.walkable = data.get("walkable", [])
	chunk.layers = data.get("layers", {})
	for key in (mutations as Dictionary).keys():
		var cell := String(key).split(",")
		if cell.size() == 2:
			chunk.mutate(
				cell[0].to_int(),
				cell[1].to_int(),
				bool((mutations[key] as Dictionary).get("blocked", false))
			)
	return chunk


## Dependency order over the registered layers. A requirement no pass
## provides fails here with its name, before any pixel is imagined.
func _order() -> Array:
	var order: Array = []
	var provided := {}
	var pending := layers()
	while not pending.is_empty():
		var progressed := false
		for layer in pending.duplicate():
			var stage := _passes[layer] as WorldmapContract
			var ready := true
			for need in stage.requires():
				if not provided.has(String(need)):
					ready = false
					break
			if ready:
				order.append(layer)
				provided[String(layer)] = true
				pending.erase(layer)
				progressed = true
		if not progressed:
			push_error("WorldmapGenerator: unsatisfiable requires() among %s" % str(pending))
			return []
	return order
