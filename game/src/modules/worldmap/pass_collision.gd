class_name WorldmapCollisionPass
extends WorldmapContract

## Collision: the walkable grid from water terrain and blocking footprints.
## Requires every props writer (`terrain`, `scatter`, `roads`, `resources`,
## `structures`, `landmarks`) and runs last among the WRITERS — anything
## placed after it would stand on cells already judged walkable, which is how
## a prop ends up inside a wall. `navigation` and `metadata` read after it;
## both are readers, and nothing may require them. Water blocks by archetype
## prefix; props block their footprint cells when the placement says
## `blocking`.


func pass_id() -> StringName:
	return &"collision"


func requires() -> Array:
	return [&"terrain", &"scatter", &"roads", &"resources", &"structures", &"landmarks"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var terrain := chunk.get("terrain", []) as Array
	var props := chunk.get("props", []) as Array
	var walkable: Array = []
	for y in size:
		var row: Array = []
		for x in size:
			row.append(_terrain_open(terrain, x, y))
		walkable.append(row)
	for prop in props:
		var placement := prop as Dictionary
		if not bool(placement.get("blocking", false)):
			continue
		var cell := placement.get("cell", Vector2i.ZERO) as Vector2i
		var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
		for dy in fp.y:
			for dx in fp.x:
				var cx: int = cell.x + dx
				var cy: int = cell.y + dy
				if cx >= 0 and cy >= 0 and cx < size and cy < size:
					(walkable[cy] as Array)[cx] = false
	return {"walkable": walkable}


func _terrain_open(terrain: Array, x: int, y: int) -> bool:
	if y < 0 or y >= terrain.size():
		return false
	var row := terrain[y] as Array
	if x < 0 or x >= row.size():
		return false
	return not String(row[x]).begins_with("water_feature")
