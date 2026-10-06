class_name BuildingApi
extends RefCounted

## Public facade for the `clan_building` module (ADR 0126). Other modules may
## reference ONLY this file (`api.gd`). Concrete implementations live beside
## this file and are wired in `app/`.
##
## ## Buildings grant infrastructure, never power
##
## ADR 0064: a clan hands out **recognition, never power**. Buildings grant
## non-combat bonuses and unlock verbs; they never directly modify combat stats.
##
## ## Yin-yang: every advantage carries its counterpart
##
## Each building costs contribution per day in upkeep. Unpaid upkeep for 3 days
## makes the building inactive. After 30 days unpaid, the building loses a level.
## Overextension (total_building_levels > clan_level * 3) halves all bonuses.
## Rival sabotage can destroy a level, prevented by Defensive Works.

const _PROVIDER_COMPONENT := &"building_provider"
const MODULE_KEY := BuildingState.MODULE_KEY

## The stat-provider component slot.
const PROVIDER_SLOT := &"building_provider"


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict`
## carried, normalizes it against the current catalog, and registers the
## provider. Idempotent.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var provider := actor.component(_PROVIDER_COMPONENT) as BuildingProvider
	if provider == null:
		provider = BuildingProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var ledger := BuildingState.normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)


## Construct a building. Returns the gate verdict `{ok, reason, unmet}`.
## Refuses when requirements are unmet, changing nothing.
static func construct(actor: Actor, building_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "null_actor", "unmet": []}
	var def := BuildingCatalog.instance().building_definition(building_id)
	if def == null:
		return {"ok": false, "reason": "unknown_building", "unmet": []}
	var gate := BuildingGate.evaluate(actor, {"verb": &"can_construct", "building_id": building_id})
	if not bool(gate.get("ok", false)):
		return gate
	var ledger := BuildingState.with_building_level(_ledger(actor), building_id, 1)
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)
	return {"ok": true, "reason": "", "unmet": []}


## Upgrade a building to the next level. Returns the gate verdict.
static func upgrade(actor: Actor, building_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "null_actor", "unmet": []}
	var def := BuildingCatalog.instance().building_definition(building_id)
	if def == null:
		return {"ok": false, "reason": "unknown_building", "unmet": []}
	var gate := BuildingGate.evaluate(actor, {"verb": &"can_upgrade", "building_id": building_id})
	if not bool(gate.get("ok", false)):
		return gate
	var current := BuildingState.building_level(_ledger(actor), building_id)
	var ledger := BuildingState.with_building_level(_ledger(actor), building_id, current + 1)
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)
	return {"ok": true, "reason": "", "unmet": []}


## Demolish a building (remove it entirely). Returns true on success.
static func demolish(actor: Actor, building_id: StringName) -> bool:
	if actor == null:
		return false
	var ledger := BuildingState.with_building_level(_ledger(actor), building_id, 0)
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)
	return true


## Assign a duty to a building (placeholder for future duty system).
static func assign_duty(actor: Actor, building_id: StringName, duty_id: StringName) -> bool:
	if actor == null:
		return false
	# Duty assignment is a placeholder for future implementation.
	return BuildingState.is_active(_ledger(actor), building_id)


## Pay upkeep for all buildings. Returns the total upkeep paid.
static func pay_upkeep(actor: Actor) -> int:
	if actor == null:
		return 0
	var ledger := _ledger(actor)
	var total := 0
	for key in BuildingState.buildings(ledger).keys():
		var entry: Dictionary = BuildingState.buildings(ledger)[key]
		var level := int(entry.get("level", 0))
		if level > 0:
			var def := BuildingCatalog.instance().building_definition(StringName(key))
			if def != null:
				total += def.upkeep_at(level)
				ledger = BuildingState.with_upkeep_paid(ledger, StringName(key))
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)
	return total


## Get the building state ledger for an actor.
static func building_state(actor: Actor) -> Dictionary:
	if actor == null:
		return BuildingState.empty()
	return BuildingState.normalize(actor.get_module_data(MODULE_KEY))


## Get a summary of all buildings for display.
static func building_summary(actor: Actor) -> Dictionary:
	var catalog := BuildingCatalog.instance()
	var out := {
		"has_actor": actor != null,
		"clan_level": 0,
		"is_overextended": false,
		"overextension_factor": 1.0,
		"total_levels": 0,
		"upkeep_due": 0,
		"buildings": {},
		"techs": [],
	}
	if actor == null:
		return out
	var ledger := _ledger(actor)
	out["clan_level"] = BuildingProjection.clan_level(ledger)
	out["is_overextended"] = BuildingProjection.is_overextended(ledger)
	out["overextension_factor"] = BuildingProjection.overextension_factor(ledger)
	out["total_levels"] = BuildingState.total_levels(ledger)
	out["techs"] = BuildingState.techs(ledger)
	var upkeep := 0
	for key in BuildingState.buildings(ledger).keys():
		var entry: Dictionary = BuildingState.buildings(ledger)[key]
		var level := int(entry.get("level", 0))
		var active := bool(entry.get("active", false))
		var days_unpaid := int(entry.get("days_unpaid", 0))
		var def := catalog.building_definition(StringName(key))
		if def != null:
			if active:
				upkeep += def.upkeep_at(level)
			out["buildings"][String(key)] = {
				"id": String(key),
				"display_name": def.display_name,
				"category": String(def.category),
				"level": level,
				"max_level": def.max_level,
				"active": active,
				"days_unpaid": days_unpaid,
				"upkeep": def.upkeep_at(level) if active else 0,
				"bonuses": def.bonuses_at(level),
				"verbs_unlocked": def.verbs_at(level),
			}
	out["upkeep_due"] = upkeep
	return out


## Check if a building can be constructed. Returns the gate verdict.
static func can_construct(actor: Actor, building_id: StringName) -> Dictionary:
	return BuildingGate.evaluate(actor, {"verb": &"can_construct", "building_id": building_id})


## Get the current clan level (1-5).
static func clan_level(actor: Actor) -> int:
	return BuildingProjection.clan_level(_ledger(actor))


## Get the tech tree with research status.
static func tech_tree(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	var researched := BuildingState.techs(ledger)
	var out := {"researched": researched, "available": [], "locked": []}
	# Tech tree is authored data; placeholder for 12 techs unlocked by clan level
	for i in range(1, 13):
		var tech_id := StringName("tech_%02d" % i)
		var tech_level := ((i - 1) / 3) + 1  # 3 techs per clan level
		var entry := {
			"id": String(tech_id),
			"unlock_clan_level": tech_level,
			"researched": researched.has(String(tech_id)),
		}
		if researched.has(String(tech_id)):
			out["available"].append(entry)
		elif BuildingProjection.clan_level(ledger) >= tech_level:
			out["available"].append(entry)
		else:
			out["locked"].append(entry)
	return out


## Research a tech. Returns the gate verdict.
static func research(actor: Actor, tech_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "null_actor", "unmet": []}
	var gate := BuildingGate.evaluate(actor, {"verb": &"can_research", "tech_id": tech_id})
	if not bool(gate.get("ok", false)):
		return gate
	var ledger := BuildingState.with_tech(_ledger(actor), tech_id)
	actor.set_module_data(MODULE_KEY, ledger)
	BuildingProjection.apply(actor, ledger)
	return {"ok": true, "reason": "", "unmet": []}


# --- Internals ---------------------------------------------------------------


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return BuildingState.empty()
	return BuildingState.normalize(actor.get_module_data(MODULE_KEY))
