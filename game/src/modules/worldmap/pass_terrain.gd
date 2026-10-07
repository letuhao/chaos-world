class_name WorldmapTerrainPass
extends WorldmapContract

## Base ground: every cell gets a ground-tile archetype of the map's
## environment, mostly the first ground tile with seeded variation where the
## catalog offers more. Provides the `terrain` layer every later pass reads.


func pass_id() -> StringName:
	return &"terrain"


func run(ctx: Dictionary, _chunk: Dictionary) -> Dictionary:
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	# Hybrid maps: an authored grid wins where provided, and generation fills
	# the rest around it. The layer contract is unchanged — later passes read
	# `terrain` without knowing which cells were authored — so an authored
	# town square and procedural wilderness are one chunk, not two systems.
	if ctx.has("authored_terrain"):
		var authored := (ctx["authored_terrain"] as Array).duplicate(true)
		if authored.size() == size:
			return {"terrain": authored}
	var grounds := WorldmapAssets.matching(environment, "ground_tile", "ground_tile.base_ground")
	if grounds.is_empty():
		grounds = WorldmapAssets.for_environment(environment).filter(
			func(entry: Dictionary) -> bool:
				return String(entry.get("category", "")) == "ground_tile"
		)
	var rows: Array = []
	for y in size:
		var row: Array = []
		for x in size:
			var pick = WorldmapRng.pick(seed, "terrain", y * size + x, grounds)
			if pick == null:
				row.append("")
			else:
				row.append(String((pick as Dictionary).get("archetype", "")))
		rows.append(row)
	return {"terrain": rows}
