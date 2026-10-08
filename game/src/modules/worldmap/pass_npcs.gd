class_name WorldmapNpcsPass
extends WorldmapContract

## NPC spawn markers: data-only (`layers["npc_spawns"]`: `cell`, `role`),
## one per structure prop plus stragglers from the `ctx` `npc_roles` list.
## Requires `terrain` and `structures` so markers gather around built ground:
## a marker stands beside its structure's door (first open cell of the
## footprint's south edge, else the structure's own cell), and roles without
## structures get no marker rather than a hermit in the wilderness. Capped at
## 8 per chunk; an empty roles list writes nothing.


func pass_id() -> StringName:
	return &"npc_spawns"


func requires() -> Array:
	return [&"terrain", &"structures"]


func run(ctx: Dictionary, chunk: Dictionary) -> Dictionary:
	var size := int(ctx.get("size", 16))
	var seed := int(ctx.get("seed", 0))
	var roles := ctx.get("npc_roles", []) as Array
	if roles.is_empty():
		return {"npc_spawns": []}
	var terrain := chunk.get("terrain", []) as Array
	var marks: Array = []
	var index := 0
	for prop in chunk.get("props", []) as Array:
		if marks.size() >= 8 or index >= roles.size():
			break
		var placement := prop as Dictionary
		if not String(placement.get("archetype", "")).begins_with("settlement_and_domain_prop"):
			continue
		var at := _doorstep(terrain, placement, size)
		if at == Vector2i(-1, -1):
			continue
		var raw = roles[index]
		var role := ""
		var npc_id := ""
		if raw is Dictionary:
			role = String((raw as Dictionary).get("role", ""))
			npc_id = String((raw as Dictionary).get("npc_id", ""))
		else:
			role = String(raw)
		var mark := {"cell": [at.x, at.y], "role": role}
		# A role is what the ground answers; an id names the individual when
		# content knows one, so a marker can reach a conversation directly.
		if not npc_id.is_empty():
			mark["npc_id"] = npc_id
		marks.append(mark)
		index += 1
	return {"npc_spawns": marks}


func _doorstep(terrain: Array, placement: Dictionary, size: int) -> Vector2i:
	var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
	var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
	for dx in fp.x:
		var at := Vector2i(base.x + dx, base.y + fp.y)
		if at.x < 0 or at.y < 0 or at.x >= size or at.y >= size:
			continue
		var row := terrain[at.y] as Array
		if not String(row[at.x]).begins_with("water_feature"):
			return at
	return Vector2i(-1, -1)
