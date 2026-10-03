class_name CombatDuel
extends RefCounted

## The player's record of the fights they have lost, persisted on the actor under
## `module_data["combat_duel"]` so a loss survives a save (ADR 0027's pattern: a plain
## versioned dictionary applied through `Actor.set_module_data`, never a serialized type).
##
## A defeat is the only thing this records. `LootApi` owns what a run is worth and what a
## run costs; `combat` owns that the player was beaten, and by what, so a screen can say
## so. Kept deliberately thin — the fight's own state (whose vitality is spent) belongs to
## the encounter that owns it.

const SCHEMA_VERSION := 1
const MODULE_KEY := &"combat_duel"

## How many recent defeats are remembered by name. A bounded ring, not a history: the
## count is the durable fact and the last few entries are the readable ones.
const HISTORY_LIMIT := 5


static func blank() -> Dictionary:
	return {"version": SCHEMA_VERSION, "defeats": 0, "last_defeat": {}, "history": []}


## A usable record from anything `module_data` may hold. A payload written before a field
## existed loads with that field empty rather than failing, and the version is stamped on
## the way out.
static func normalize(raw: Dictionary) -> Dictionary:
	var duel := blank()
	if raw.is_empty():
		return duel
	duel["defeats"] = maxi(0, int(raw.get("defeats", 0)))
	if raw.get("last_defeat") is Dictionary:
		duel["last_defeat"] = (raw["last_defeat"] as Dictionary).duplicate(true)
	if raw.get("history") is Array:
		duel["history"] = (raw["history"] as Array).duplicate(true).slice(-HISTORY_LIMIT)
	duel["version"] = SCHEMA_VERSION
	return duel


## Record one defeat: `taken` is the share of the player's health the final blow spent.
static func record_defeat(duel: Dictionary, entry: Dictionary) -> Dictionary:
	duel["defeats"] = int(duel.get("defeats", 0)) + 1
	duel["last_defeat"] = entry.duplicate(true)
	var history: Array = duel.get("history", [])
	history.append(entry.duplicate(true))
	duel["history"] = history.slice(-HISTORY_LIMIT)
	duel["version"] = SCHEMA_VERSION
	return duel


## Primitives only, so a panel can render it without naming this class.
static func view(duel: Dictionary) -> Dictionary:
	return {
		"defeats": int(duel.get("defeats", 0)),
		"last_defeat": (duel.get("last_defeat", {}) as Dictionary).duplicate(true),
		"history": (duel.get("history", []) as Array).duplicate(true),
	}
