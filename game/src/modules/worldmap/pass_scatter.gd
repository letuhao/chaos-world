class_name WorldmapScatterPass
extends WorldmapContract

## Vegetation and props: deterministic scatter of catalog assets over ground
## that is not water. Requires `terrain`. Each configured entry names an
## archetype, a density, and whether it blocks; the asset itself is picked by
## index from the catalog match, so new art for the same archetype joins the
## rotation with no code change. Footprints that would leave the chunk are
## skipped rather than clipped — a clipped prop is a prop standing half off
## its own ground.


func pass_id() -> StringName:
	return &"scatter"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var terrain := chunk.get("terrain", []) as Array
	var entries := ctx.get("scatter", []) as Array
	var props: Array = []
	var index := 0
	for y in size:
		for x in size:
			if _is_water(terrain, x, y):
				continue
			for entry in entries:
				var row := entry as Dictionary
				var density := float(row.get("density", 0.0))
				if density <= 0.0:
					continue
				if WorldmapRng.unit(seed, "scatter", index) > density:
					index += 1
					continue
				index += 1
				var prop := _place(seed, index, environment, row, x, y, size)
				if not prop.is_empty():
					props.append(prop)
	return {"props": props}


func _is_water(terrain: Array, x: int, y: int) -> bool:
	if y < 0 or y >= terrain.size():
		return true
	var row := terrain[y] as Array
	if x < 0 or x >= row.size():
		return true
	return String(row[x]).begins_with("water_feature")


func _place(
	seed: int, index: int, environment: String, entry: Dictionary, x: int, y: int, size: int
) -> Dictionary:
	var archetype := String(entry.get("archetype", ""))
	var parts := archetype.split(".")
	if parts.size() != 2:
		return {}
	var matches := WorldmapAssets.matching(environment, parts[0], archetype)
	if matches.is_empty():
		return {}
	var asset := WorldmapRng.pick(seed, "scatter_asset", index, matches) as Dictionary
	var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
	if x + fp.x > size or y + fp.y > size:
		return {}
	return {
		"asset": String(asset.get("id", "")),
		"archetype": archetype,
		"cell": Vector2i(x, y),
		"footprint": fp,
		"blocking": bool(entry.get("blocking", true)),
		"z": y + fp.y,
	}
