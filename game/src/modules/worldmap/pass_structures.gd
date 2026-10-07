class_name WorldmapStructuresPass
extends WorldmapContract

## Structures and settlements: counted placements with clearance (huts,
## storehouses, altars, bridges) and plot-group hamlets from `settlements`
## entries (`plots: [{archetype, dx, dy}]`, `count`, `spacing`). Requires
## `terrain`, `scatter` and `resources` so clearance reads every prop placed
## before it. A plot that overlaps, leaves the chunk, or names missing art is
## skipped whole — half a hamlet is a promise the map cannot keep. Count caps
## at 6 structures and 2 settlements per chunk: a chunk is ground with things
## on it, not a town.


func pass_id() -> StringName:
	return &"structures"


func requires() -> Array:
	return [&"terrain", &"scatter", &"resources"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var terrain := chunk.get("terrain", []) as Array
	var placed := (chunk.get("props", []) as Array).duplicate(true)
	var out: Array = []
	var cursor := 0
	for entry in (ctx.get("structures", []) as Array).duplicate():
		if out.size() >= 6:
			break
		cursor += 1
		var prop := _single(seed, cursor, environment, entry as Dictionary, terrain, placed, size)
		if not prop.is_empty():
			out.append(prop)
			placed.append(prop)
	for entry in (ctx.get("settlements", []) as Array).duplicate():
		if _settlement_count(out) >= 2:
			break
		cursor += 1
		var plots := _hamlet(seed, cursor, environment, entry as Dictionary, terrain, placed, size)
		for prop in plots:
			out.append(prop)
			placed.append(prop)
	return {"props": out}


func _single(
	seed: int,
	index: int,
	environment: String,
	entry: Dictionary,
	terrain: Array,
	placed: Array,
	size: int
) -> Dictionary:
	var archetype := String(entry.get("archetype", ""))
	var at := _ground_cell(seed, index, environment, archetype, terrain, placed, size, 1)
	if at == Vector2i(-1, -1):
		return {}
	return _prop(seed, index, environment, archetype, at, bool(entry.get("blocking", true)), {})


func _hamlet(
	seed: int,
	index: int,
	environment: String,
	entry: Dictionary,
	terrain: Array,
	placed: Array,
	size: int
) -> Array:
	var plots := entry.get("plots", []) as Array
	if plots.is_empty():
		return []
	var spacing := maxi(1, int(entry.get("spacing", 3)))
	var built: Array = []
	for attempt in 8:
		var ox := WorldmapRng.range_i(seed, "hamlet_x", index * 8 + attempt, 0, size)
		var oy := WorldmapRng.range_i(seed, "hamlet_y", index * 8 + attempt, 0, size)
		var trial: Array = []
		var fits := true
		for plot in plots:
			var row := plot as Dictionary
			var archetype := String(row.get("archetype", ""))
			var at := Vector2i(ox + int(row.get("dx", 0)), oy + int(row.get("dy", 0)))
			var prop := _prop(
				seed, index, environment, archetype, at, true, {"hamlet": "hamlet_%d" % index}
			)
			if prop.is_empty() or not _clear_of(prop, placed, built, spacing):
				fits = false
				break
			if not _on_ground(terrain, prop, size):
				fits = false
				break
			trial.append(prop)
		if fits:
			for prop in trial:
				built.append(prop)
			return built
	return []


func _ground_cell(
	seed: int,
	index: int,
	environment: String,
	archetype: String,
	terrain: Array,
	placed: Array,
	size: int,
	margin: int
) -> Vector2i:
	var cells := WorldmapPlacement.open_cells(terrain, size)
	if cells.is_empty():
		return Vector2i(-1, -1)
	for attempt in mini(cells.size(), 24):
		var at := WorldmapRng.pick(seed, "structure_cell", index * 24 + attempt, cells) as Vector2i
		var matches := _assets(environment, archetype)
		if matches.is_empty():
			return Vector2i(-1, -1)
		var asset := WorldmapRng.pick(seed, "structure_asset", index, matches) as Dictionary
		var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
		if not WorldmapPlacement.footprint_fits(at, fp, size):
			continue
		if _clear_of({"cell": at, "footprint": fp}, placed, [], margin):
			return at
	return Vector2i(-1, -1)


func _clear_of(candidate: Dictionary, placed: Array, built: Array, margin: int) -> bool:
	var cell := candidate.get("cell", Vector2i(-1, -1)) as Vector2i
	var fp := candidate.get("footprint", Vector2i.ONE) as Vector2i
	for prop in placed + built:
		var row := prop as Dictionary
		if WorldmapPlacement.rects_overlap(
			cell,
			fp,
			row.get("cell", Vector2i(-1, -1)) as Vector2i,
			row.get("footprint", Vector2i.ONE) as Vector2i,
			margin
		):
			return false
	return true


func _on_ground(terrain: Array, prop: Dictionary, size: int) -> bool:
	var cell := prop.get("cell", Vector2i(-1, -1)) as Vector2i
	var fp := prop.get("footprint", Vector2i.ONE) as Vector2i
	if not WorldmapPlacement.footprint_fits(cell, fp, size):
		return false
	for dy in fp.y:
		for dx in fp.x:
			var row := terrain[cell.y + dy] as Array
			if String(row[cell.x + dx]).begins_with("water_feature"):
				return false
	return true


func _prop(
	seed: int,
	index: int,
	environment: String,
	archetype: String,
	at: Vector2i,
	blocking: bool,
	extra: Dictionary
) -> Dictionary:
	var matches := _assets(environment, archetype)
	if matches.is_empty():
		return {}
	var asset := WorldmapRng.pick(seed, "structure_asset", index, matches) as Dictionary
	var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
	var prop := {
		"asset": String(asset.get("id", "")),
		"archetype": archetype,
		"cell": at,
		"footprint": fp,
		"blocking": blocking,
		"z": at.y + fp.y,
	}
	for key in extra.keys():
		prop[key] = extra[key]
	return prop


func _assets(environment: String, archetype: String) -> Array:
	var parts := archetype.split(".")
	if parts.size() != 2:
		return []
	return WorldmapAssets.matching(environment, parts[0], archetype)


func _settlement_count(props: Array) -> int:
	var hamlets := {}
	for prop in props:
		if (prop as Dictionary).has("hamlet"):
			hamlets[String((prop as Dictionary).get("hamlet", ""))] = true
	return hamlets.size()
