class_name WorldmapAuthoredPass
extends WorldmapContract

## Authored props: hand-placed placements on an otherwise procedural chunk —
## the hybrid map in one pass. Reads `ctx` `authored`, a list of patches each
## naming its chunk (`{"chunk": [cx, cy], "props": [{archetype, cell: [x, y],
## blocking, yield?, poi?}], "cleared": [[x, y], ...]}`); only the patch for
## THIS chunk applies, so an anchor belongs to a place instead of standing in
## every chunk of the node. Resolves art from the catalog (footprint from the
## art, never from the config) and emits props for later scatter-family
## passes to respect. Requires `terrain` and runs before `scatter`/
## `resources`, so decor roots AROUND an anchor instead of through it — the
## one ordering this pass exists for.
## A placement that names missing art, leaves the chunk, carries a malformed
## cell, or stands on water is refused LOUDLY and skipped: a pinned anchor is
## a promise the map must keep, so a broken pin reports itself rather than
## vanishing. The FIRST entry marked `poi` also writes `layers["landmark"]`
## with `suggests_edge` derived from the archetype by the same rule the
## landmarks pass uses — an authored gate names the chunk exactly once.


func pass_id() -> StringName:
	return &"authored"


func requires() -> Array:
	return [&"terrain"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var patch := WorldmapPlacement.authored_patch(ctx)
	if patch.is_empty():
		return {"props": []}
	var environment := String(ctx.get("environment", ""))
	var size := int(ctx.get("size", 16))
	var terrain := chunk.get("terrain", []) as Array
	var props: Array = []
	var landmark := {}
	for entry in patch.get("props", []) as Array:
		var prop := _place(environment, entry as Dictionary, terrain, size)
		if prop.is_empty():
			continue
		props.append(prop)
		if landmark.is_empty() and bool((entry as Dictionary).get("poi", false)):
			var at := prop.get("cell", Vector2i.ZERO) as Vector2i
			landmark = {
				"archetype": String(prop.get("archetype", "")),
				"cell": [at.x, at.y],
				"suggests_edge":
				(
					String(prop.get("archetype", "")).ends_with("cave_entrance")
					or String(prop.get("archetype", "")).ends_with("domain_entrance")
				),
			}
	var out := {"props": props}
	if not landmark.is_empty():
		out["landmark"] = landmark
	return out


func _place(environment: String, entry: Dictionary, terrain: Array, size: int) -> Dictionary:
	var archetype := String(entry.get("archetype", "")) if entry != null else ""
	var parts := archetype.split(".")
	if parts.size() != 2:
		return {}
	var matches := WorldmapAssets.matching(environment, parts[0], archetype)
	if matches.is_empty():
		push_error("WorldmapAuthoredPass: no art for '%s' in %s" % [archetype, environment])
		return {}
	var at := entry.get("cell", []) as Array
	if at.size() != 2:
		push_error("WorldmapAuthoredPass: malformed cell for '%s'" % archetype)
		return {}
	var cell := Vector2i(int(at[0]), int(at[1]))
	var asset := matches[0] as Dictionary
	var fp := asset.get("footprint", Vector2i.ONE) as Vector2i
	if not WorldmapPlacement.footprint_fits(cell, fp, size):
		push_error("WorldmapAuthoredPass: '%s' at %s leaves the chunk" % [archetype, str(cell)])
		return {}
	for dy in fp.y:
		for dx in fp.x:
			if WorldmapPlacement.cell_is_water(terrain, cell.x + dx, cell.y + dy):
				push_error(
					"WorldmapAuthoredPass: '%s' at %s stands on water" % [archetype, str(cell)]
				)
				return {}
	var harvest := {}
	for key in (entry.get("yield", {}) as Dictionary).keys():
		var amount = (entry.get("yield", {}) as Dictionary).get(key)
		if (amount is int or amount is float) and not (amount is bool):
			harvest[String(key)] = maxi(0, int(amount))
	return {
		"asset": String(asset.get("id", "")),
		"archetype": archetype,
		"cell": cell,
		"footprint": fp,
		"blocking": bool(entry.get("blocking", true)),
		"yield": harvest,
		"z": cell.y + fp.y,
	}
