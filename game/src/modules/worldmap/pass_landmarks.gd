class_name WorldmapLandmarksPass
extends WorldmapContract

## Landmarks: at most one named point of interest per chunk (a statue, a
## ruined arch, a cave mouth), placed clear of every earlier prop and written
## both as a visible prop and as `layers["landmark"]` (`archetype`, `cell`,
## `suggests_edge`). An entrance archetype suggests — never builds — a travel
## edge: wiring the graph is an authored act, and a generator that grew edges
## would redraw the world's connectivity every time its seed moved. Requires
## `terrain`, `scatter`, `resources` and `structures` so the one landmark
## never lands inside anything. Density from `ctx` `landmark_density`
## (default 0.15); candidates from `ctx` `landmarks` (default arch + statue).


func pass_id() -> StringName:
	return &"landmarks"


func requires() -> Array:
	return [&"terrain", &"scatter", &"resources", &"structures"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	if WorldmapRng.unit(seed, "landmark_roll", 0) > float(ctx.get("landmark_density", 0.15)):
		return {"props": []}
	var candidates: Array = [
		"landmark_and_environment_detail.ruined_arch",
		"landmark_and_environment_detail.statue",
	]
	if ctx.get("landmarks", []) is Array and not (ctx.get("landmarks", []) as Array).is_empty():
		candidates = (ctx.get("landmarks", []) as Array).duplicate()
	var placed := chunk.get("props", []) as Array
	var terrain := chunk.get("terrain", []) as Array
	for attempt in 12:
		var archetype := String(WorldmapRng.pick(seed, "landmark_kind", attempt, candidates))
		var at := _ground_cell(seed, attempt, environment, archetype, terrain, placed, size)
		if at == Vector2i(-1, -1):
			continue
		var prop := _prop(seed, attempt, environment, archetype, at)
		if prop.is_empty():
			continue
		return {
			"props": [prop],
			"landmark":
			{
				"archetype": archetype,
				"cell": [at.x, at.y],
				"suggests_edge":
				archetype.ends_with("cave_entrance") or archetype.ends_with("domain_entrance"),
			},
		}
	return {"props": []}


func _ground_cell(
	seed: int,
	attempt: int,
	environment: String,
	archetype: String,
	terrain: Array,
	placed: Array,
	size: int
) -> Vector2i:
	var cells := WorldmapPlacement.open_cells(terrain, size)
	if cells.is_empty():
		return Vector2i(-1, -1)
	for pick in mini(cells.size(), 16):
		var at := WorldmapRng.pick(seed, "landmark_cell", attempt * 16 + pick, cells) as Vector2i
		var matches := _assets(environment, archetype)
		if matches.is_empty():
			return Vector2i(-1, -1)
		var fp := (matches[0] as Dictionary).get("footprint", Vector2i.ONE) as Vector2i
		if not WorldmapPlacement.footprint_fits(at, fp, size):
			continue
		if WorldmapPlacement.cell_taken(placed, at):
			continue
		var clear := true
		for prop in placed:
			var row := prop as Dictionary
			if WorldmapPlacement.rects_overlap(
				at,
				fp,
				row.get("cell", Vector2i(-1, -1)) as Vector2i,
				row.get("footprint", Vector2i.ONE) as Vector2i,
				1
			):
				clear = false
				break
		if clear:
			return at
	return Vector2i(-1, -1)


func _prop(
	seed: int, index: int, environment: String, archetype: String, at: Vector2i
) -> Dictionary:
	var matches := _assets(environment, archetype)
	if matches.is_empty():
		return {}
	var asset := WorldmapRng.pick(seed, "landmark_asset", index, matches) as Dictionary
	var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
	return {
		"asset": String(asset.get("id", "")),
		"archetype": archetype,
		"cell": at,
		"footprint": fp,
		"blocking": not archetype.ends_with("cave_entrance"),
		"z": at.y + fp.y,
	}


func _assets(environment: String, archetype: String) -> Array:
	var parts := archetype.split(".")
	if parts.size() != 2:
		return []
	return WorldmapAssets.matching(environment, parts[0], archetype)
