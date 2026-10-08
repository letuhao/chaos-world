class_name WorldmapResourcesPass
extends WorldmapContract

## Resources: harvestable archetypes (ore veins, herbs, crystal) scattered
## over open ground, each placement carrying its `yield` payload
## (`{kind: amount}`) for whoever harvests it. Requires `terrain`; entries
## come from the `ctx` `resources` list (`archetype`, `density`,
## `blocking`, `yield`). Props APPEND to earlier passes' — the pipeline
## concatenates `props`, so order among scatter-family passes never loses a
## placement.


func pass_id() -> StringName:
	return &"resources"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var terrain := chunk.get("terrain", []) as Array
	var entries := ctx.get("resources", []) as Array
	var props: Array = []
	if entries.is_empty():
		return {"props": props}
	var cells := WorldmapPlacement.open_cells(terrain, size)
	var stood := chunk.get("props", []) as Array
	var cleared := WorldmapPlacement.cleared_cells(
		WorldmapPlacement.authored_patch(ctx).get("cleared", []) as Array
	)
	var index := 0
	for cell in cells:
		var at := cell as Vector2i
		for entry in entries:
			var row := entry as Dictionary
			var density := float(row.get("density", 0.0))
			index += 1
			if density <= 0.0 or WorldmapRng.unit(seed, "resource", index) > density:
				continue
			var prop := _place(seed, index, environment, row, at, size, stood, cleared)
			if not prop.is_empty():
				props.append(prop)
	return {"props": props}


func _place(
	seed: int,
	index: int,
	environment: String,
	entry: Dictionary,
	at: Vector2i,
	size: int,
	stood: Array,
	cleared: Array
) -> Dictionary:
	var archetype := String(entry.get("archetype", ""))
	var parts := archetype.split(".")
	if parts.size() != 2:
		return {}
	var matches := WorldmapAssets.matching(environment, parts[0], archetype)
	if matches.is_empty():
		return {}
	var asset := WorldmapRng.pick(seed, "resource_asset", index, matches) as Dictionary
	var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
	if not WorldmapPlacement.footprint_fits(at, fp, size):
		return {}
	# Sealed ground grows nothing: an authored anchor holds, so a vein never
	# surfaces inside a gate, and a reserved door pad stays clear.
	if WorldmapPlacement.footprint_taken(stood, at, fp):
		return {}
	if WorldmapPlacement.footprint_cleared(at, fp, cleared):
		return {}
	var harvest := {}
	for key in (entry.get("yield", {}) as Dictionary).keys():
		var amount = (entry.get("yield", {}) as Dictionary).get(key)
		if (amount is int or amount is float) and not (amount is bool):
			harvest[String(key)] = maxi(0, int(amount))
	return {
		"asset": String(asset.get("id", "")),
		"archetype": archetype,
		"cell": at,
		"footprint": fp,
		"blocking": bool(entry.get("blocking", true)),
		"yield": harvest,
		"z": at.y + fp.y,
	}
