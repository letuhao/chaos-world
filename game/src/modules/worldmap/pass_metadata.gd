class_name WorldmapMetadataPass
extends WorldmapContract

## Gameplay metadata: one summary of everything the chunk holds
## (`layers["metadata"]`: `chunk`, `seed`, `environment`, `size`, `regions`,
## `walkable_cells`, `blocked_cells`, `pois`). POIs collect the landmark, the
## encounter marks, the NPC markers and every settlement prop — each as
## `{kind, cell, ...}` primitives — so encounter, quest and spawn systems
## read one address instead of re-walking every layer. Requires everything it
## summarizes and writes nothing any other pass reads: it runs last of all,
## and nothing may require it. A metadata that excluded a layer would be a
## second, disagreeing index, so the POI sweep reads the same layers the
## pipeline folded.


func pass_id() -> StringName:
	return &"metadata"


func requires() -> Array:
	return [
		&"terrain",
		&"elevation",
		&"scatter",
		&"resources",
		&"structures",
		&"landmarks",
		&"roads",
		&"encounters",
		&"npc_spawns",
		&"navigation",
		&"collision",
	]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var layers := chunk.get("layers", {}) as Dictionary
	var walkable := chunk.get("walkable", []) as Array
	var size := int(ctx.get("size", 16))
	var open := 0
	for row in walkable:
		for cell in row as Array:
			if bool(cell):
				open += 1
	var nav := layers.get("navigation", {}) as Dictionary
	var pois: Array = []
	var landmark := layers.get("landmark", {}) as Dictionary
	if not landmark.is_empty():
		(
			pois
			. append(
				{
					"kind": "landmark",
					"cell": (landmark.get("cell", [0, 0]) as Array).duplicate(),
					"archetype": String(landmark.get("archetype", "")),
				}
			)
		)
	for mark in layers.get("encounters", []) as Array:
		var row := mark as Dictionary
		(
			pois
			. append(
				{
					"kind": "encounter",
					"cell": (row.get("cell", [0, 0]) as Array).duplicate(),
					"table": String(row.get("table", "")),
				}
			)
		)
	for mark in layers.get("npc_spawns", []) as Array:
		var row := mark as Dictionary
		var npc_poi := {
			"kind": "npc",
			"cell": (row.get("cell", [0, 0]) as Array).duplicate(),
			"role": String(row.get("role", "")),
		}
		if String(row.get("npc_id", "")) != "":
			npc_poi["npc_id"] = String(row.get("npc_id", ""))
		pois.append(npc_poi)
	for prop in chunk.get("props", []) as Array:
		var placement := prop as Dictionary
		var arch := String(placement.get("archetype", ""))
		if arch.begins_with("settlement_and_domain_prop"):
			var at := placement.get("cell", Vector2i.ZERO) as Vector2i
			pois.append({"kind": "structure", "cell": [at.x, at.y], "archetype": arch})
	return {
		"metadata":
		{
			"chunk":
			(
				"%s:%d,%d"
				% [String(ctx.get("node", "")), int(ctx.get("cx", 0)), int(ctx.get("cy", 0))]
			),
			"seed": int(ctx.get("seed", 0)),
			"environment": String(ctx.get("environment", "")),
			"size": size,
			"regions":
			{
				"count": int(nav.get("count", 0)),
				"largest": int(nav.get("largest", -1)),
			},
			"walkable_cells": open,
			"blocked_cells": size * size - open,
			"pois": pois,
		}
	}
