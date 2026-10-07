class_name WorldmapStreamer
extends RefCounted

## Which chunks exist right now, and in what form. Three ranges, three costs:
## data (generated and cached — cheap), scene (instantiated Node2D subtrees),
## render (visible). A chunk outside the scene range costs a dictionary; only
## inside it costs nodes. Ranges are radii in chunks around a focus chunk and
## may differ per map; the only invariant is scene <= data, because a scene
## with no data behind it is a picture of nothing.
##
## Mutations live here, keyed by chunk id, so unload/reload keeps exactly
## what changed: regeneration replays the seed, then the overlay reapplies.

var data_radius: int = 2
var scene_radius: int = 1
var _generator: WorldmapGenerator = null
var _config: Dictionary = {}
var _mutations: Dictionary = {}
var _data_cache: Dictionary = {}
var _loaded: Dictionary = {}


func configure(generator: WorldmapGenerator, config: Dictionary) -> void:
	_generator = generator
	_config = (config as Dictionary).duplicate(true)


## The chunk at `(cx, cy)`, generated and cached. Mutations reapply on every
## regeneration, so a cached copy and a fresh one agree.
func chunk_data(node_id: String, cx: int, cy: int, size: int, seed: int) -> WorldChunk:
	var id := "%s:%d,%d" % [node_id, cx, cy]
	if _data_cache.has(id):
		return _data_cache[id] as WorldChunk
	var chunk := _generator.generate(node_id, cx, cy, size, seed, _config, _mutations.get(id, {}))
	_data_cache[id] = chunk
	return chunk


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
## and to every future regeneration through the overlay.
func mutate(node_id: String, cx: int, cy: int, x: int, y: int, blocked: bool) -> void:
	var id := "%s:%d,%d" % [node_id, cx, cy]
	var overlay := _mutations.get(id, {}) as Dictionary
	overlay["%d,%d" % [x, y]] = {"blocked": blocked}
	_mutations[id] = overlay
	if _data_cache.has(id):
		(_data_cache[id] as WorldChunk).mutate(x, y, blocked)


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


## Primitives only: what is cached, loaded, and mutated.
func summary() -> Dictionary:
	return {
		"cached": _data_cache.size(),
		"loaded": loaded_ids(),
		"mutated_chunks": _mutations.keys(),
		"data_radius": data_radius,
		"scene_radius": scene_radius,
	}


## The mutation overlay as the save envelope should carry it: chunk id ->
## cell key -> `{"blocked": bool}`. Untouched chunks are absent, never empty:
## regeneration reproduces them from the seed, so persisting them would be a
## second copy of the world that could disagree with the first.
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
