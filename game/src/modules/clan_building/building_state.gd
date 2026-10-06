class_name BuildingState
extends RefCounted

## The versioned building ledger, stored as a plain dictionary under
## `actor.module_data["building_state"]` (ADR 0027 pattern).
##
## **This ledger is the single source of truth.** The projection is derived
## and rebuilt from here on every attach.
##
## ## The schema
##
## `{version, buildings, techs_researched, last_upkeep_paid}`.
## `buildings` maps building_id to `{level, days_unpaid, active}`.
## `techs_researched` is an array of tech ids.
## `last_upkeep_paid` is the tick count when upkeep was last paid.

const SCHEMA_VERSION := 1
const MODULE_KEY := &"building_state"

## Days before an unpaid building becomes inactive.
const INACTIVE_THRESHOLD := 3
## Days before an unpaid building loses a level.
const DECAY_THRESHOLD := 30


static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"buildings": {},
		"techs_researched": [],
		"last_upkeep_paid": 0,
	}


## Normalize a payload from a save into a valid ledger.
static func normalize(payload: Dictionary) -> Dictionary:
	var out := empty()
	if payload.is_empty():
		return out
	if not (payload.get("version", 0) is int):
		return out
	out["version"] = int(payload["version"])
	var buildings = payload.get("buildings", {})
	if buildings is Dictionary:
		for key in (buildings as Dictionary).keys():
			var entry = (buildings as Dictionary)[key]
			if entry is Dictionary:
				var level := int(entry.get("level", 0))
				var days_unpaid := int(entry.get("days_unpaid", 0))
				var active := bool(entry.get("active", true))
				if level > 0:
					out["buildings"][String(key)] = {
						"level": level,
						"days_unpaid": days_unpaid,
						"active": active,
					}
	var techs = payload.get("techs_researched", [])
	if techs is Array:
		for t in techs:
			if t is String or t is StringName:
				out["techs_researched"].append(String(t))
	var last_paid = payload.get("last_upkeep_paid", 0)
	if last_paid is int or last_paid is float:
		out["last_upkeep_paid"] = int(last_paid)
	return out


## The buildings map from the ledger.
static func buildings(ledger: Dictionary) -> Dictionary:
	var b = ledger.get("buildings", {})
	return b if b is Dictionary else {}


## The level of a specific building, 0 if not constructed.
static func building_level(ledger: Dictionary, building_id: StringName) -> int:
	var b = buildings(ledger)
	var entry = b.get(String(building_id), {})
	if entry is Dictionary:
		return int(entry.get("level", 0))
	return 0


## Whether a building is active (constructed and not inactive).
static func is_active(ledger: Dictionary, building_id: StringName) -> bool:
	var b = buildings(ledger)
	var entry = b.get(String(building_id), {})
	if not (entry is Dictionary):
		return false
	return int(entry.get("level", 0)) > 0 and bool(entry.get("active", false))


## Days unpaid for a building.
static func days_unpaid(ledger: Dictionary, building_id: StringName) -> int:
	var b = buildings(ledger)
	var entry = b.get(String(building_id), {})
	if entry is Dictionary:
		return int(entry.get("days_unpaid", 0))
	return 0


## Total building levels across all buildings.
static func total_levels(ledger: Dictionary) -> int:
	var total := 0
	for key in buildings(ledger).keys():
		total += building_level(ledger, StringName(key))
	return total


## Set a building's level. Removes the entry if level is 0.
static func with_building_level(
	ledger: Dictionary, building_id: StringName, level: int
) -> Dictionary:
	var out := normalize(ledger)
	if level <= 0:
		out["buildings"].erase(String(building_id))
	else:
		var entry: Dictionary = out["buildings"].get(String(building_id), {})
		entry["level"] = level
		entry["days_unpaid"] = 0
		entry["active"] = true
		out["buildings"][String(building_id)] = entry
	return out


## Increment days unpaid for a building. Deactivates if threshold reached.
static func with_days_unpaid(ledger: Dictionary, building_id: StringName, days: int) -> Dictionary:
	var out := normalize(ledger)
	var entry: Dictionary = out["buildings"].get(String(building_id), {})
	if entry.is_empty():
		return out
	entry["days_unpaid"] = int(entry.get("days_unpaid", 0)) + days
	if int(entry["days_unpaid"]) >= INACTIVE_THRESHOLD:
		entry["active"] = false
	out["buildings"][String(building_id)] = entry
	return out


## Reset days unpaid for a building (after paying upkeep).
static func with_upkeep_paid(ledger: Dictionary, building_id: StringName) -> Dictionary:
	var out := normalize(ledger)
	var entry: Dictionary = out["buildings"].get(String(building_id), {})
	if entry.is_empty():
		return out
	entry["days_unpaid"] = 0
	entry["active"] = true
	out["buildings"][String(building_id)] = entry
	return out


## Apply maintenance decay: buildings unpaid >= DECAY_THRESHOLD lose 1 level.
static func with_decay(ledger: Dictionary) -> Dictionary:
	var out := normalize(ledger)
	for key in out["buildings"].keys():
		var entry: Dictionary = out["buildings"][key]
		if int(entry.get("days_unpaid", 0)) >= DECAY_THRESHOLD:
			var new_level := int(entry.get("level", 0)) - 1
			if new_level <= 0:
				out["buildings"].erase(key)
			else:
				entry["level"] = new_level
				entry["days_unpaid"] = 0
				entry["active"] = true
	return out


## Add a tech to the researched list.
static func with_tech(ledger: Dictionary, tech_id: StringName) -> Dictionary:
	var out := normalize(ledger)
	if not out["techs_researched"].has(String(tech_id)):
		out["techs_researched"].append(String(tech_id))
	return out


## Whether a tech has been researched.
static func has_tech(ledger: Dictionary, tech_id: StringName) -> bool:
	return normalize(ledger)["techs_researched"].has(String(tech_id))


## The techs researched array.
static func techs(ledger: Dictionary) -> Array:
	return normalize(ledger)["techs_researched"]
