class_name WorldmapElevationPass
extends WorldmapContract

## Elevation: a height per cell (0 low, 1 level, 2 high) as pure data on the
## `elevation` layer. Patchy rather than per-cell noise: coarse 3x3 blocks
## roll once and cells inherit their block with a small jitter, so hills read
## as ground rather than static. Requires `terrain` for pipeline order.
## Nothing blocks on height yet — cliffs are a 4b structure, and this layer
## is what they will read.


func pass_id() -> StringName:
	return &"elevation"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, _chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var rows: Array = []
	for y in size:
		var row: Array = []
		for x in size:
			# Integer division groups cells into 3x3 blocks; the jitter keeps
			# block edges from reading as cliffs.
			var block := WorldmapRng.range_i(seed, "elev_block", (y / 3) * 64 + x / 3, 0, 3)
			var jitter := WorldmapRng.range_i(seed, "elev_jitter", y * size + x, -1, 2)
			row.append(clampi(block + jitter, 0, 2))
		rows.append(row)
	return {"elevation": rows}
