class_name DestinyState
extends RefCounted

## The versioned fate/destiny ledger, stored as a plain dictionary under
## `actor.module_data["destiny_state"]` (ADR 0027 pattern). Core persists it
## without ever naming a destiny type.
##
## This ledger is the single source of truth. `actor.traits` carries a
## `destiny:`-namespaced mirror for cheap reads through `StatContext.has_trait`,
## but the mirror is derived and is rebuilt from here on every attach — never
## trusted.
##
## **The earn-only invariant.** Nothing in this module removes a fate or a
## destiny. Not a penalty, not a reset, not a debug affordance, not a save
## migration. `normalize()` may *drop* an entry only when it is unreadable or
## names content the catalog no longer ships — it can never drop one because the
## player did something. That distinction is the whole design (ADR 0065).

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"destiny_state"
## The history trail is a bounded explanation of what the player is owed, not a
## full audit log. A save cannot grow without limit.
const HISTORY_LIMIT := 128
## Every stat modifier fate contributes is tagged with this prefix, so a
## re-projection can strip and rebuild the whole contribution from the ledger.
const SOURCE_PREFIX := "destiny:"
## The `Actor.traits` mirror prefix.
const TRAIT_PREFIX := "destiny:"


## The stat source id one fate or destiny contributes under.
static func source_for(id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, id])


## The `Actor.traits` mirror id one fate or destiny is reflected under.
static func trait_for(id: StringName) -> StringName:
	return StringName("%s%s" % [TRAIT_PREFIX, id])


## True when a stat modifier source belongs to this module.
static func is_own_source(source: StringName) -> bool:
	return String(source).begins_with(SOURCE_PREFIX)


## A known-fate filter for this module. `known_fates` / `known_destinies` come
## from the catalog; an entry naming content that no longer ships is dropped
## rather than persisted, so a save from a wider content build cannot smuggle in
## a fate the current build does not define.
static func normalize(
	payload: Dictionary, known_fates: Dictionary = {}, known_destinies: Dictionary = {}
) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"fates": {},
		"destinies": {},
		"counters": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	# A payload that cannot be read is diagnosed as empty, never partially
	# applied. Half a ledger is worse than none: it would silently change what
	# the player is owed.
	var fates = payload.get("fates", {})
	if fates is Dictionary:
		for fate_id in (fates as Dictionary).keys():
			var entry = (fates as Dictionary)[fate_id]
			if not _is_fate_entry(entry):
				continue
			if not known_fates.is_empty() and not known_fates.has(String(fate_id)):
				continue
			out["fates"][String(fate_id)] = {
				"source": String((entry as Dictionary).get("source", "")),
				"sequence": int((entry as Dictionary).get("sequence", 0)),
			}
	var destinies = payload.get("destinies", {})
	if destinies is Dictionary:
		for destiny_id in (destinies as Dictionary).keys():
			var entry = (destinies as Dictionary)[destiny_id]
			if not (entry is Dictionary):
				continue
			if not known_destinies.is_empty() and not known_destinies.has(String(destiny_id)):
				continue
			out["destinies"][String(destiny_id)] = {
				"source": String((entry as Dictionary).get("source", "")),
				"sequence": int((entry as Dictionary).get("sequence", 0)),
				"bearing": String((entry as Dictionary).get("bearing", "")),
			}
	var counters = payload.get("counters", {})
	if counters is Dictionary:
		for counter_id in (counters as Dictionary).keys():
			var value = (counters as Dictionary)[counter_id]
			if not (value is int or value is float) or int(value) < 0:
				continue
			out["counters"][String(counter_id)] = int(value)
	var history = payload.get("history", [])
	if history is Array:
		for record in history as Array:
			if not (record is Dictionary):
				continue
			# Rebuilt field by field rather than duplicated, because a file-backed
			# save makes one JSON hop and JSON has a single number type: a copied
			# `sequence` comes back as 2.0 and the ledger stops comparing equal to
			# itself across a save. Every other ledger field is coerced the same way.
			var entry := record as Dictionary
			(
				out["history"]
				. append(
					{
						"kind": String(entry.get("kind", "")),
						"id": String(entry.get("id", "")),
						"detail": String(entry.get("detail", "")),
						"sequence": int(entry.get("sequence", 0)),
					}
				)
			)
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


static func _is_fate_entry(entry) -> bool:
	return entry is Dictionary and (entry as Dictionary).has("source")


## True when `fate_id` is recorded. The only question a gate may ask about
## holding.
static func has_fate(ledger: Dictionary, fate_id: StringName) -> bool:
	return (ledger.get("fates", {}) as Dictionary).has(String(fate_id))


## True when `destiny_id` is recorded.
static func has_destiny(ledger: Dictionary, destiny_id: StringName) -> bool:
	return (ledger.get("destinies", {}) as Dictionary).has(String(destiny_id))


## Every held fate id, canonically ordered.
static func fate_ids(ledger: Dictionary) -> Array[StringName]:
	return _sorted_keys(ledger.get("fates", {}) as Dictionary)


## Every held destiny id, canonically ordered.
static func destiny_ids(ledger: Dictionary) -> Array[StringName]:
	return _sorted_keys(ledger.get("destinies", {}) as Dictionary)


# --- Internals -------------------------------------------------------------


## A dictionary's keys as StringNames, ordered by their STRING value.
##
## Not `out.sort()`: `Array[StringName].sort()` is not specified to order by
## StringName's string value, and the ids are interned, so the result can depend
## on which id was loaded first. The order is load-bearing — a codex cycling the
## list must not reorder itself between reads — so it is pinned to the one
## comparison that cannot drift.
static func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## The counter value, or 0 when it was never recorded. A counter never
## decreases, so a missing counter and a zero counter are the same answer.
static func counter_value(ledger: Dictionary, counter_id: StringName) -> int:
	return int((ledger.get("counters", {}) as Dictionary).get(String(counter_id), 0))
