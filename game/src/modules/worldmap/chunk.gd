class_name WorldChunk
extends RefCounted

## One generated chunk: cells plus the overlay that survives regeneration.
## `walkable`/`terrain` are rows of plain values; `props` is an array of
## placement dicts (`{asset, cell, footprint, z}`); `mutations` maps
## `"x,y"` to `{"blocked": bool}`, applied OVER regeneration — so an
## untouched chunk is reproducible from its seed alone, while a touched one
## keeps exactly what changed and nothing else. `layers` carries every later
## pass layer (`elevation`, encounters, ...) by the pass's own name, so a new
## pass never migrates this shape: first-class fields stay three, and the
## fourth is a map keyed by whoever wrote it.

var id: String = ""
var node: String = ""
var cx: int = 0
var cy: int = 0
var size: int = 16
var seed: int = 0
var walkable: Array = []
var terrain: Array = []
var props: Array = []
var mutations: Dictionary = {}
var layers: Dictionary = {}


static func make(
	chunk_id: String, node_id: String, chunk_x: int, chunk_y: int, chunk_size: int, chunk_seed: int
) -> WorldChunk:
	var chunk := WorldChunk.new()
	chunk.id = chunk_id
	chunk.node = node_id
	chunk.cx = chunk_x
	chunk.cy = chunk_y
	chunk.size = maxi(1, chunk_size)
	chunk.seed = chunk_seed
	chunk.walkable = []
	chunk.terrain = []
	for _y in range(chunk.size):
		var walk_row: Array = []
		var terrain_row: Array = []
		for _x in range(chunk.size):
			walk_row.append(true)
			terrain_row.append("")
		chunk.walkable.append(walk_row)
		chunk.terrain.append(terrain_row)
	return chunk


## Whether a unit can stand on chunk-local `(x, y)`: inside, walkable, and not
## sealed by a mutation. The one answer to "can I stand here".
func standable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= size or y >= size:
		return false
	var mutation := mutations.get("%d,%d" % [x, y], {}) as Dictionary
	if not mutation.is_empty() and mutation.has("blocked"):
		return not bool(mutation["blocked"])
	return bool((walkable[y] as Array)[x])


## Whether `(x, y)` is spent ground: a harvested node the seed must not grow
## back. Separate from `blocked` on purpose — harvesting a vein frees the cell
## it sealed, and a second visit still finds it picked, not regrown.
func spent(x: int, y: int) -> bool:
	return bool((mutations.get("%d,%d" % [x, y], {}) as Dictionary).get("spent", false))


## Whether every cell of a placement is spent. A prop is consumed whole, so a
## footprint with any spent cell is a consumed node.
func prop_spent(placement: Dictionary) -> bool:
	var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
	var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
	for dy in fp.y:
		for dx in fp.x:
			if spent(base.x + dx, base.y + dy):
				return true
	return false


## Record a persistent change. Mutations are the ONLY thing a save must
## persist for a touched chunk; everything else regenerates. `spent` is
## written only when true, so a plain seal/free keeps the one-key shape every
## reader already knows.
func mutate(x: int, y: int, blocked: bool, spent_one: bool = false) -> void:
	var row := {"blocked": blocked}
	if spent_one:
		row["spent"] = true
	mutations["%d,%d" % [x, y]] = row


## Primitives only, for a save envelope or a test.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"node": node,
		"cx": cx,
		"cy": cy,
		"size": size,
		"seed": seed,
		"walkable": walkable.duplicate(true),
		"terrain": terrain.duplicate(true),
		"props": props.duplicate(true),
		"mutations": mutations.duplicate(true),
		"layers": layers.duplicate(true),
	}


static func from_dict(data: Dictionary) -> WorldChunk:
	var chunk := WorldChunk.new()
	chunk.id = String(data.get("id", ""))
	chunk.node = String(data.get("node", ""))
	chunk.cx = int(data.get("cx", 0))
	chunk.cy = int(data.get("cy", 0))
	chunk.size = maxi(1, int(data.get("size", 16)))
	chunk.seed = int(data.get("seed", 0))
	chunk.walkable = (data.get("walkable", []) as Array).duplicate(true)
	chunk.terrain = (data.get("terrain", []) as Array).duplicate(true)
	chunk.props = (data.get("props", []) as Array).duplicate(true)
	chunk.mutations = (data.get("mutations", {}) as Dictionary).duplicate(true)
	chunk.layers = (data.get("layers", {}) as Dictionary).duplicate(true)
	return chunk
