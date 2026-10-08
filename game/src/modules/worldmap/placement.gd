class_name WorldmapPlacement
extends RefCounted

## Shared placement math for the scatter-family passes. One place, so every
## pass agrees on what "fits", what "overlaps" and which cells are ground —
## and a second, drifting answer can never grow beside the first. Pure and
## deterministic: same inputs, same placements.


## Whether a footprint rooted at `cell` stays inside a `size` chunk. Skipped,
## never clipped: a clipped prop stands half off its own ground.
static func footprint_fits(cell: Vector2i, fp: Vector2i, size: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x + fp.x <= size and cell.y + fp.y <= size


## Whether two footprint rects touch within `margin` cells. The margin is what
## keeps a shelter out of a canopy and a roadside shrine off the road.
static func rects_overlap(
	a_cell: Vector2i, a_fp: Vector2i, b_cell: Vector2i, b_fp: Vector2i, margin: int = 0
) -> bool:
	return (
		a_cell.x - margin < b_cell.x + b_fp.x
		and b_cell.x - margin < a_cell.x + a_fp.x
		and a_cell.y - margin < b_cell.y + b_fp.y
		and b_cell.y - margin < a_cell.y + a_fp.y
	)


## Every non-water cell of a terrain grid, in row order. Water is read by
## archetype prefix — the same rule the collision pass seals by — so the two
## can never disagree about what is ground.
static func open_cells(terrain: Array, size: int) -> Array:
	var out: Array = []
	if terrain.size() != size:
		return out
	for y in size:
		var row := terrain[y] as Array
		if row.size() != size:
			continue
		for x in size:
			if not String(row[x]).begins_with("water_feature"):
				out.append(Vector2i(x, y))
	return out


## Whether `cell` (a single cell) is sealed by any blocking prop already
## placed. Footprint-aware: a canopy's trunk cell counts, its shade does not —
## the same rule destruction credits.
static func cell_taken(props: Array, cell: Vector2i) -> bool:
	for prop in props:
		var placement := prop as Dictionary
		if not bool(placement.get("blocking", false)):
			continue
		var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
		var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
		if (
			cell.x >= base.x
			and cell.y >= base.y
			and cell.x < base.x + fp.x
			and cell.y < base.y + fp.y
		):
			return true
	return false


## Whether a cell is sealed by water. Terrain is rows of archetype strings;
## `water_feature.*` is the one family that cannot carry a prop.
static func cell_is_water(terrain: Array, x: int, y: int) -> bool:
	if y < 0 or y >= terrain.size():
		return true
	var row := terrain[y] as Array
	if x < 0 or x >= row.size():
		return true
	return String(row[x]).begins_with("water_feature")


## The authored patch for THIS chunk, or `{}`. A patch names its chunk
## (`{"chunk": [cx, cy], "props": [...], "cleared": [...]}`) because authored
## ground belongs to a PLACE: the first draft applied the same pins to every
## chunk of the node, which planted the starter shelter in each preloaded
## neighbour and reported itself on their water (measured 2026-10-08).
static func authored_patch(ctx: Dictionary) -> Dictionary:
	var cell := [int(ctx.get("cx", 0)), int(ctx.get("cy", 0))]
	for patch in ctx.get("authored", []) as Array:
		if patch is Dictionary and ((patch as Dictionary).get("chunk", []) as Array) == cell:
			return patch as Dictionary
	return {}


## The config's reserved cells as `Vector2i`s. Config authors `[x, y]` pairs;
## the placement math wants cells, so one conversion lives here rather than
## in every pass.
static func cleared_cells(raw: Array) -> Array:
	var out: Array = []
	for cell in raw:
		if cell is Vector2i:
			out.append(cell)
		elif cell is Array and (cell as Array).size() == 2:
			out.append(Vector2i(int((cell as Array)[0]), int((cell as Array)[1])))
	return out


## Sealed ground also grows nothing: a placement never takes a cell the
## config reserved (a door pad, a clearing). What is reserved is reserved for
## the author, not for the seed.
static func footprint_cleared(cell: Vector2i, fp: Vector2i, cleared: Array) -> bool:
	for dy in fp.y:
		for dx in fp.x:
			if Vector2i(cell.x + dx, cell.y + dy) in cleared:
				return true
	return false


## Whether any cell of a footprint rooted at `cell` is sealed. What a
## scatter or resource pass asks before rooting something broad.
static func footprint_taken(props: Array, cell: Vector2i, fp: Vector2i) -> bool:
	for dy in fp.y:
		for dx in fp.x:
			if cell_taken(props, Vector2i(cell.x + dx, cell.y + dy)):
				return true
	return false
