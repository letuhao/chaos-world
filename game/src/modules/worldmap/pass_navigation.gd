class_name WorldmapNavigationPass
extends WorldmapContract

## Navigation: connected walkable regions over the generated ground
## (`layers["navigation"]`: `regions` rows of region ids, `count`, `largest`,
## `sizes`). Requires `terrain` and `collision`. Flood-fill with an index
## pointer (never `pop_front`, which is linear per pop) and a visited set, so
## the walk is bounded by the cell count however the water meanders. Regions
## label the GENERATED ground: post-generation mutations can re-split a
## region, so exact answers still go through `standable` and regions stay
## coarse — a region says "this hangs together", never "every step lands".


func pass_id() -> StringName:
	return &"navigation"


func requires() -> Array:
	return [&"terrain", &"collision"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var walkable := chunk.get("walkable", []) as Array
	if walkable.size() != size:
		return {"navigation": {"regions": [], "count": 0, "largest": -1, "sizes": {}}}
	var regions: Array = []
	for _y in size:
		var row: Array = []
		for _x in size:
			row.append(-1)
		regions.append(row)
	var sizes := {}
	var next_id := 0
	for y in size:
		for x in size:
			if not bool((walkable[y] as Array)[x]) or int((regions[y] as Array)[x]) >= 0:
				continue
			var cells := _flood(walkable, regions, size, x, y, next_id)
			sizes[next_id] = cells
			next_id += 1
	var largest := -1
	var best := -1
	for id in sizes.keys():
		if int(sizes[id]) > best:
			best = int(sizes[id])
			largest = int(id)
	return {
		"navigation": {"regions": regions, "count": next_id, "largest": largest, "sizes": sizes}
	}


func _flood(walkable: Array, regions: Array, size: int, sx: int, sy: int, id: int) -> int:
	var cells := 0
	var queue: Array = [Vector2i(sx, sy)]
	(regions[sy] as Array)[sx] = id
	var head := 0
	while head < queue.size():
		var at := queue[head] as Vector2i
		head += 1
		cells += 1
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + delta
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
				continue
			if not bool((walkable[next.y] as Array)[next.x]):
				continue
			if int((regions[next.y] as Array)[next.x]) >= 0:
				continue
			(regions[next.y] as Array)[next.x] = id
			queue.append(next)
	return cells
