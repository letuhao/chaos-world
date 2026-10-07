class_name WorldmapRoadsPass
extends WorldmapContract

## Roads: meandering packed-trail bands carved over the terrain the earlier
## passes laid. Requires `terrain`, `elevation` and `scatter` so it speaks
## last among the terrain writers. A road skips water cells and high ground
## (height 2): the gap at a stream is a ford or a bridge the structures pass
## will span, not a trail painted over open water. Count comes from the `ctx`
## `roads` key (default 0 — a cave or a test opts in); a missing trail
## archetype for the environment skips carving rather than holing the map.


func pass_id() -> StringName:
	return &"roads"


func requires() -> Array:
	return [&"terrain", &"elevation", &"scatter"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var terrain := (chunk.get("terrain", []) as Array).duplicate(true)
	if terrain.size() != size:
		return {"terrain": terrain}
	var count := int(ctx.get("roads", 0))
	if count <= 0:
		return {"terrain": terrain}
	if (
		WorldmapAssets
		. by_archetype(String(ctx.get("environment", "")), "ground_tile.packed_trail")
		. is_empty()
	):
		return {"terrain": terrain}
	var elevation := (chunk.get("layers", {}) as Dictionary).get("elevation", []) as Array
	for road in mini(count, 4):
		_carve(seed + road * 101, terrain, elevation, size)
	return {"terrain": terrain}


func _carve(seed: int, terrain: Array, elevation: Array, size: int) -> void:
	# One band per road, bounded by the chunk: the loop walks columns (or rows)
	# and drifts, so it cannot run past an edge or revisit a decision.
	var horizontal := WorldmapRng.range_i(seed, "road_axis", 0, 0, 2) == 0
	var line := WorldmapRng.range_i(seed, "road_line", 1, 1, maxi(2, size - 1))
	for i in size:
		line = clampi(line + WorldmapRng.range_i(seed, "road_drift", i, -1, 2), 1, size - 2)
		var x := i if horizontal else line
		var y := line if horizontal else i
		if _blocked_ground(terrain, elevation, x, y, size):
			continue
		(terrain[y] as Array)[x] = "ground_tile.packed_trail"


func _blocked_ground(terrain: Array, elevation: Array, x: int, y: int, size: int) -> bool:
	if y < 0 or y >= size:
		return true
	var row := terrain[y] as Array
	if x < 0 or x >= row.size():
		return true
	if String(row[x]).begins_with("water_feature"):
		return true
	if elevation.size() == size and (elevation[y] as Array).size() == size:
		if int((elevation[y] as Array)[x]) >= 2:
			return true
	return false
