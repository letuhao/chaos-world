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
