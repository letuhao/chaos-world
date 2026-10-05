class_name EncounterState
extends RefCounted

## The versioned encounter ledger, stored as a plain dictionary under
## `actor.module_data["encounter_state"]` (ADR 0027 pattern).
##
## Tracks which encounters have been seen and resolved. Monotone: an encounter
## is seen once and stays seen (ADR 0065 earn-only). An encounter can be
## resolved (the player made a fate choice) or dismissed (the player skipped it).
##
## The state also tracks cooldowns: the last turn each encounter triggered,
## so the same encounter cannot fire again until the cooldown has passed.

const SCHEMA_VERSION := 1
const MODULE_KEY := &"encounter_state"
## The history trail is a bounded explanation of what the player experienced.
const HISTORY_LIMIT := 64


## Normalize a payload from `actor.module_data` into a clean ledger.
static func normalize(payload: Dictionary) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"seen": {},
		"resolved": {},
		"cooldowns": {},
		"prophecies_earned": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	var seen = payload.get("seen", {})
	if seen is Dictionary:
		for encounter_id in (seen as Dictionary).keys():
			out["seen"][String(encounter_id)] = true
	var resolved = payload.get("resolved", {})
	if resolved is Dictionary:
		for encounter_id in (resolved as Dictionary).keys():
			var entry = (resolved as Dictionary)[encounter_id]
			if entry is Dictionary:
				out["resolved"][String(encounter_id)] = {
					"fate_id": String((entry as Dictionary).get("fate_id", "")),
					"sequence": int((entry as Dictionary).get("sequence", 0)),
				}
	var cooldowns = payload.get("cooldowns", {})
	if cooldowns is Dictionary:
		for encounter_id in (cooldowns as Dictionary).keys():
			out["cooldowns"][String(encounter_id)] = int((cooldowns as Dictionary)[encounter_id])
	var prophecies = payload.get("prophecies_earned", {})
	if prophecies is Dictionary:
		for prophecy_id in (prophecies as Dictionary).keys():
			out["prophecies_earned"][String(prophecy_id)] = true
	var history = payload.get("history", [])
	if history is Array:
		for record in history as Array:
			if not (record is Dictionary):
				continue
			var entry := record as Dictionary
			out["history"].append({
				"kind": String(entry.get("kind", "")),
				"id": String(entry.get("id", "")),
				"detail": String(entry.get("detail", "")),
				"sequence": int(entry.get("sequence", 0)),
			})
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## Whether an encounter has been seen.
static func has_seen(ledger: Dictionary, encounter_id: StringName) -> bool:
	return (ledger.get("seen", {}) as Dictionary).has(String(encounter_id))


## Whether an encounter has been resolved (fate choice made).
static func has_resolved(ledger: Dictionary, encounter_id: StringName) -> bool:
	return (ledger.get("resolved", {}) as Dictionary).has(String(encounter_id))


## The fate_id chosen when resolving an encounter, or empty string.
static func resolved_fate(ledger: Dictionary, encounter_id: StringName) -> String:
	var resolved = ledger.get("resolved", {}) as Dictionary
	var entry = resolved.get(String(encounter_id), {})
	if entry is Dictionary:
		return String((entry as Dictionary).get("fate_id", ""))
	return ""


## Whether a prophecy has been earned.
static func has_prophecy(ledger: Dictionary, prophecy_id: StringName) -> bool:
	return (ledger.get("prophecies_earned", {}) as Dictionary).has(String(prophecy_id))


## The turn an encounter last triggered, or 0.
static func cooldown_turn(ledger: Dictionary, encounter_id: StringName) -> int:
	return int((ledger.get("cooldowns", {}) as Dictionary).get(String(encounter_id), 0))


## Whether an encounter is on cooldown at the given turn.
static func on_cooldown(ledger: Dictionary, encounter_id: StringName, current_turn: int, cooldown: int) -> bool:
	if cooldown <= 0:
		return false
	var cooldowns = ledger.get("cooldowns", {}) as Dictionary
	if not cooldowns.has(String(encounter_id)):
		return false
	var last := int(cooldowns[String(encounter_id)])
	return (current_turn - last) < cooldown


## Every prophecy earned, canonically ordered.
static func prophecies_earned(ledger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var earned = ledger.get("prophecies_earned", {}) as Dictionary
	for key in earned.keys():
		out.append(StringName(key))
	out.sort()
	return out
