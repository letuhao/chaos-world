class_name WorldmapWaterPass
extends WorldmapContract

## Water: carves one meandering stream across the chunk over the terrain the
## terrain pass laid. Requires `terrain` — a stream with no ground under it
## is a drawing error, refused here rather than painted. Stream cells carry
## water archetypes; the collision pass (not this one) decides they block,
## because "water exists" and "water blocks" are different answers.


func pass_id() -> StringName:
	return &"water"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var terrain := (chunk.get("terrain", []) as Array).duplicate(true)
	if terrain.size() != size:
		return {"terrain": terrain}
	# A map may decline water entirely (caves do): no stream is carved and the
	# terrain stands as laid.
	if ctx.get("water", true) == false:
		return {"terrain": terrain}
	var y := WorldmapRng.range_i(seed, "water_row", 0, 2, maxi(3, size - 2))
	for x in size:
		y = clampi(y + WorldmapRng.range_i(seed, "water_drift", x, -1, 2), 1, size - 2)
		(terrain[y] as Array)[x] = "water_feature.stream"
		if y + 1 < size:
			(terrain[y + 1] as Array)[x] = "water_feature.shallow_water"
	return {"terrain": terrain}
