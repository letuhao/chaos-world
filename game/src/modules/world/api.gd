class_name WorldApi
extends RefCounted

## Public facade for the `world` module (ADR 0019).
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

## Valid world tiers.
const VALID_TIERS: Array[StringName] = [&"micro", &"small", &"great"]


## Query: world tier identifier.
static func tier(actor: Actor) -> String:
	if actor == null or actor.world == null:
		return ""
	return String(actor.world.tier)


## Query: active laws as primitive dictionaries.
static func laws(actor: Actor) -> Array[Dictionary]:
	if actor == null or actor.world == null:
		return []
	var out: Array[Dictionary] = []
	for law in actor.world.laws:
		out.append(law.to_dict())
	return out


## Query: current inhabitants as primitive dictionaries.
static func inhabitants(actor: Actor) -> Array[Dictionary]:
	if actor == null or actor.world == null:
		return []
	var out: Array[Dictionary] = []
	for inhabitant in actor.world.inhabitants:
		out.append(inhabitant.to_dict())
	return out


## Query: available resources.
static func resources(actor: Actor) -> Dictionary:
	if actor == null or actor.world == null:
		return {}
	return actor.world.resources.duplicate()


## Query: all world location definitions as primitive dictionaries, in the SCAN order
## consumers already know (`WorldSpawnApi.random` sorts by `location_id` itself before
## its draw, so a re-sorted read here would only move the ground under it). Each row
## names the authored FACTION and TIER the location belongs to
## (`faction_name`/`tier_name`, LOC keys a reader resolves) — the raw ids were the
## only thing the authored faction and tier catalogs ever reached production with
## (BL-0227).
static func locations(_actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open("res://data/world/locations")
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := "res://data/world/locations/%s" % file_name
			var def := load(path) as WorldLocationDef
			if def != null:
				(
					out
					. append(
						{
							"location_id": String(def.location_id),
							"display_name": def.display_name,
							"tier": String(def.tier),
							"tier_name": WorldDefIndex.display_name(&"tier", def.tier),
							"faction_id": String(def.faction_id),
							"faction_name": WorldDefIndex.display_name(&"faction", def.faction_id),
							"resources": def.resources.duplicate(),
							"inhabitant_types": def.inhabitant_types.duplicate(),
							"danger_level": def.danger_level,
						}
					)
				)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## Action: create a new world. Returns result dictionary.
static func create_world(actor: Actor, tier: StringName, size: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if not VALID_TIERS.has(tier):
		return {"ok": false, "reason": "invalid_tier", "tier": String(tier)}
	if size <= 0.0:
		return {"ok": false, "reason": "invalid_size", "size": size}
	actor.world = WorldState.new(tier, size)
	return {"ok": true, "tier": String(tier), "size": size}


## Action: add a law to the world. Returns result dictionary.
static func add_law(actor: Actor, law_id: StringName, value: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	if value <= 0.0:
		return {"ok": false, "reason": "invalid_value", "value": value}
	var law := WorldLawState.new(law_id, WorldLawState.SPATIAL, value)
	actor.world.add_law(law)
	return {"ok": true, "law_id": String(law_id), "value": value}


## Action: add inhabitants to the world. Returns result dictionary.
static func add_inhabitant(
	actor: Actor, inhabitant_id: StringName, type: StringName, count: int
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	if count <= 0:
		return {"ok": false, "reason": "invalid_count", "count": count}
	var inhabitant := InhabitantRef.new(inhabitant_id, type, count)
	actor.world.add_inhabitant(inhabitant)
	return {
		"ok": true, "inhabitant_id": String(inhabitant_id), "type": String(type), "count": count
	}


## Action: pay qi upkeep. Returns result dictionary.
static func pay_upkeep(actor: Actor, qi_amount: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	if qi_amount <= 0.0:
		return {"ok": false, "reason": "invalid_amount", "amount": qi_amount}
	if qi_amount < actor.world.upkeep_rate:
		return {
			"ok": false,
			"reason": "insufficient_qi",
			"required": actor.world.upkeep_rate,
			"provided": qi_amount,
		}
	return {"ok": true, "amount": qi_amount, "upkeep_rate": actor.world.upkeep_rate}


## Action: evolve world to next tier (micro->small->great). Returns result dictionary.
static func evolve_world(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	var current_tier: StringName = actor.world.tier
	var current_idx := VALID_TIERS.find(current_tier)
	if current_idx == -1:
		return {"ok": false, "reason": "unknown_tier", "tier": String(current_tier)}
	if current_idx >= VALID_TIERS.size() - 1:
		return {"ok": false, "reason": "max_tier", "tier": String(current_tier)}
	var new_tier: StringName = VALID_TIERS[current_idx + 1]
	var old_tier := current_tier
	var old_size := actor.world.size
	var new_law_slots := (current_idx + 2) * 3
	var new_size := old_size * 10.0
	actor.world.tier = new_tier
	actor.world.size = new_size
	return {
		"ok": true,
		"old_tier": String(old_tier),
		"new_tier": String(new_tier),
		"new_size": new_size,
		"new_law_slots": new_law_slots,
	}


## Action: merge target's world into actor's. Returns result dictionary.
static func merge_world(actor: Actor, target_actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if target_actor == null:
		return {"ok": false, "reason": "no_target"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	if target_actor.world == null:
		return {"ok": false, "reason": "no_target_world"}
	if actor.world.will_strength < target_actor.world.will_strength * 1.5:
		return {
			"ok": false,
			"reason": "insufficient_will",
			"required": target_actor.world.will_strength * 1.5,
			"provided": actor.world.will_strength,
		}
	var old_size := actor.world.size
	var target_size: float = target_actor.world.size
	var new_size := old_size + target_size
	for inhabitant in target_actor.world.inhabitants:
		actor.world.add_inhabitant(inhabitant)
	for key in target_actor.world.resources:
		if actor.world.resources.has(key):
			actor.world.resources[key] = (
				float(actor.world.resources[key]) + float(target_actor.world.resources[key])
			)
		else:
			actor.world.resources[key] = target_actor.world.resources[key]
	actor.world.size = new_size
	var result_tier: StringName = actor.world.tier
	var target_tier: StringName = target_actor.world.tier
	if VALID_TIERS.find(target_tier) > VALID_TIERS.find(result_tier):
		result_tier = target_tier
	return {
		"ok": true,
		"result_tier": String(result_tier),
		"result_size": new_size,
	}


## Action: trigger a world conflict. Returns result dictionary.
static func trigger_conflict(actor: Actor, conflict_id: StringName, severity: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if actor.world == null:
		return {"ok": false, "reason": "no_world"}
	if conflict_id == &"":
		return {"ok": false, "reason": "invalid_conflict_id"}
	if severity <= 0.0:
		return {"ok": false, "reason": "invalid_severity", "severity": severity}
	var stability_impact := severity * 0.1
	actor.world.stability = maxf(0.0, actor.world.stability - stability_impact)
	return {
		"ok": true,
		"conflict_id": String(conflict_id),
		"severity": severity,
		"stability_impact": stability_impact,
	}
