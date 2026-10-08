class_name WorldmapStreamer
extends RefCounted

## Which chunks exist right now, and in what form. Four ranges, four costs:
## data (generated and cached — cheap), simulation (markers live: encounters
## and spawns the game may act on), scene (instantiated Node2D subtrees),
## render (visible). A chunk outside the scene range costs a dictionary; only
## inside it costs nodes. Ranges are radii in chunks around a focus chunk and
## may differ per map; the invariants are render <= scene <= data and
## sim <= data, enforced by clamping — a scene with no data behind it is a
## picture of nothing, and a simulation without data is a decision about
## nothing.
##
## Mutations live here, keyed by chunk id, so unload/reload keeps exactly
## what changed: regeneration replays the seed, then the overlay reapplies.

var data_radius: int = 2
var sim_radius: int = 1
var scene_radius: int = 1
var render_radius: int = 1
var _generator: WorldmapGenerator = null
var _config: Dictionary = {}
var _mutations: Dictionary = {}
var _data_cache: Dictionary = {}
var _loaded: Dictionary = {}
var _focus := Vector2i.ZERO
var _cursor := {}


func configure(generator: WorldmapGenerator, config: Dictionary) -> void:
	_generator = generator
	_config = (config as Dictionary).duplicate(true)
	data_radius = maxi(0, int(_config.get("data_radius", 2)))
	sim_radius = mini(int(_config.get("sim_radius", 1)), data_radius)
	scene_radius = mini(int(_config.get("scene_radius", 1)), data_radius)
	render_radius = mini(int(_config.get("render_radius", 1)), scene_radius)


## The chunk at `(cx, cy)`, generated and cached. Mutations reapply on every
## regeneration, so a cached copy and a fresh one agree. Records the cursor
## the predictive preload walks from.
func chunk_data(node_id: String, cx: int, cy: int, size: int, seed: int) -> WorldChunk:
	var id := "%s:%d,%d" % [node_id, cx, cy]
	_cursor = {"node": node_id, "size": size, "seed": seed}
	if _data_cache.has(id):
		return _data_cache[id] as WorldChunk
	var chunk := _generator.generate(node_id, cx, cy, size, seed, _config, _mutations.get(id, {}))
	_data_cache[id] = chunk
	return chunk


## Move the focus the ranges are measured from. The scene calls this with
## every refresh, so ranges follow the player rather than the spawn.
func set_focus(focus: Vector2i) -> void:
	_focus = focus


## Chunk ids within the simulation range of the focus. Membership is the
## liveness answer: markers outside it exist but the game does not act on
## them. Bounded by definition: a radius is a square, not a walk.
func simulated() -> Array:
	var out: Array = []
	for offset in neighborhood(_focus.x, _focus.y, sim_radius):
		var id := _chunk_key(offset)
		if _data_cache.has(id):
			out.append(id)
	out.sort()
	return out


## Whether a chunk id is simulated right now.
func is_simulated(chunk_id: String) -> bool:
	for offset in neighborhood(_focus.x, _focus.y, sim_radius):
		if _chunk_key(offset) == chunk_id:
			return _data_cache.has(chunk_id)
	return false


func _chunk_key(offset: Vector2i) -> String:
	return "%s:%d,%d" % [String(_cursor.get("node", "")), offset.x, offset.y]


## Generate (never instantiate) the chunks ahead of `(dx, dy)` from the
## cursor, up to `steps` (capped at 8). Answers how many were already known
## versus newly cached, so a caller can tell prediction from waste. Pure
## data: no nodes, no visibility, nothing the player can see.
func preload_toward(dx: int, dy: int, steps: int) -> Dictionary:
	var known := 0
	var generated := 0
	if _cursor.is_empty() or _generator == null:
		return {"known": known, "generated": generated}
	var dir := Vector2i(clampi(dx, -1, 1), clampi(dy, -1, 1))
	if dir == Vector2i.ZERO:
		return {"known": known, "generated": generated}
	for step in range(1, mini(steps, 8) + 1):
		var at := _focus + dir * step
		var id := "%s:%d,%d" % [String(_cursor.get("node", "")), at.x, at.y]
		if _data_cache.has(id):
			known += 1
			continue
		chunk_data(
			String(_cursor.get("node", "")),
			at.x,
			at.y,
			int(_cursor.get("size", 16)),
			int(_cursor.get("seed", 0))
		)
		generated += 1
	return {"known": known, "generated": generated}


## Whether the scene for a chunk is instantiated.
func is_loaded(chunk_id: String) -> bool:
	return _loaded.has(chunk_id)


## Mark a chunk scene live. The scene owns its nodes; this owns the set.
func mark_loaded(chunk_id: String) -> void:
	_loaded[chunk_id] = true


## Drop a scene (nodes freed by the caller) but KEEP its data and mutations.
## Unloading forgets nothing: data stays cached, mutations stay recorded.
func unload(chunk_id: String) -> void:
	_loaded.erase(chunk_id)


## Record a persistent change on a chunk. Applies to the cached copy at once
## and to every future regeneration through the overlay. `spent` marks a
## harvested node; it rides the same overlay so one save persists both.
func mutate(
	node_id: String, cx: int, cy: int, x: int, y: int, blocked: bool, spent: bool = false
) -> void:
	var id := "%s:%d,%d" % [node_id, cx, cy]
	var overlay := _mutations.get(id, {}) as Dictionary
	var row := {"blocked": blocked}
	if spent:
		row["spent"] = true
	overlay["%d,%d" % [x, y]] = row
	_mutations[id] = overlay
	if _data_cache.has(id):
		(_data_cache[id] as WorldChunk).mutate(x, y, blocked, spent)


## Chunk ids within `radius` of a focus, in row order. Bounded by definition:
## a radius is a square, not a walk.
func neighborhood(cx: int, cy: int, radius: int) -> Array:
	var out: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			out.append(Vector2i(cx + dx, cy + dy))
	return out


## Loaded scene ids, sorted, for the debug overlay and the tests.
func loaded_ids() -> Array:
	var out := _loaded.keys()
	out.sort()
	return out


## Primitives only: what is cached, loaded, simulated and mutated, and the
## ranges in force.
func summary() -> Dictionary:
	return {
		"cached": _data_cache.size(),
		"loaded": loaded_ids(),
		"simulated": simulated(),
		"mutated_chunks": _mutations.keys(),
		"data_radius": data_radius,
		"sim_radius": sim_radius,
		"scene_radius": scene_radius,
		"render_radius": render_radius,
	}


## The mutation overlay as the save envelope should carry it: chunk id ->
## cell key -> `{"blocked": bool, "spent": bool?}`. Untouched chunks are
## absent, never empty: regeneration reproduces them from the seed, so
## persisting them would be a second copy of the world that could disagree
## with the first.
func export_mutations() -> Dictionary:
	return _mutations.duplicate(true)


## Restore an overlay a previous session exported. Replaces the live overlay
## wholesale and drops the data cache, so cached chunks regenerated under the
## old overlay cannot disagree with the restored one. The cache is knowledge,
## not state: it rebuilds from seed plus overlay on next read.
func import_mutations(overlay: Dictionary) -> void:
	var kept := {}
	for chunk_id in (overlay as Dictionary).keys():
		var cells = overlay.get(chunk_id)
		if cells is Dictionary:
			kept[String(chunk_id)] = (cells as Dictionary).duplicate(true)
	_mutations = kept
	_data_cache.clear()
