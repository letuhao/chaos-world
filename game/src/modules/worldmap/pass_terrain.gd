class_name WorldmapTerrainPass
extends WorldmapContract

## Base ground: every cell gets a ground-tile archetype from the map's
## palette (a `ctx` list of archetype Strings, defaulting to base ground
## alone), with seeded rotation across the entries. Provides the `terrain`
## layer every later pass reads. A palette entry with no catalog art for the
## environment is skipped, never painted as a hole: the pick rotates over the
## entries that exist, and an empty palette falls back to base ground.


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
	var wanted: Array = ["ground_tile.base_ground"]
	if ctx.get("palette", []) is Array and not (ctx.get("palette", []) as Array).is_empty():
		wanted = (ctx.get("palette", []) as Array).duplicate()
	var grounds: Array = []
	for archetype in wanted:
		if WorldmapAssets.by_archetype(environment, String(archetype)).is_empty():
			continue
		grounds.append(String(archetype))
	if grounds.is_empty():
		grounds = ["ground_tile.base_ground"]
	var rows: Array = []
	for y in size:
		var row: Array = []
		for x in size:
			var index := WorldmapRng.range_i(seed, "terrain", y * size + x, 0, grounds.size())
			row.append(String(grounds[index]))
		rows.append(row)
	return {"terrain": rows}
