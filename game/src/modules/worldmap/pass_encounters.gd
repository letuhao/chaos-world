class_name WorldmapEncountersPass
extends WorldmapContract

## Encounters: data-only spawn markers (`layers["encounters"]`: `cell`,
## `table`, `weight`), rolled from the `ctx` `encounter_tables` list by
## weight. Markers are not props and never render: what the player meets is
## the encounter system's to decide; the generator only says where the wild
## things are. Requires `terrain` (markers stand on open ground, never water).
## Count from `ctx` `encounter_density` (default 0 — encounters are opt-in per
## map); capped at 8 per chunk.


func pass_id() -> StringName:
	return &"encounters"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var tables := ctx.get("encounter_tables", []) as Array
	var density := float(ctx.get("encounter_density", 0.0))
	if tables.is_empty() or density <= 0.0:
		return {"encounters": []}
	var cells := WorldmapPlacement.open_cells(chunk.get("terrain", []) as Array, size)
	var total := 0.0
	for table in tables:
		total += maxi(0.0, float((table as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {"encounters": []}
	var marks: Array = []
	var index := 0
	for cell in cells:
		if marks.size() >= 8:
			break
		index += 1
		if WorldmapRng.unit(seed, "encounter", index) > density:
			continue
		var roll := WorldmapRng.unit(seed, "encounter_table", index) * total
		for table in tables:
			roll -= maxi(0.0, float((table as Dictionary).get("weight", 0.0)))
			if roll <= 0.0:
				var at := cell as Vector2i
				(
					marks
					. append(
						{
							"cell": [at.x, at.y],
							"table": String((table as Dictionary).get("id", "")),
							"weight": float((table as Dictionary).get("weight", 0.0)),
						}
					)
				)
				break
	return {"encounters": marks}
