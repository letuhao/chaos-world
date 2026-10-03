class_name RaceState
extends RefCounted

## The versioned race ledger, stored as a plain dictionary under
## `actor.module_data["race_state"]` (ADR 0027 pattern). Core persists it without ever
## naming a race.
##
## **This ledger is the single source of truth.** `actor.traits` carries a `race:`-
## namespaced mirror for cheap reads through `StatContext.has_trait`, and the actor
## carries a `race_def` component holding the resolved definition for a pure provider to
## read. Both are derived and are rebuilt from here on every attach — never trusted.
##
## **A race is assigned once, at conception, and is immutable for the actor's life**
## (ADR 0062). There is no transformation and no assimilation. What the ledger must
## therefore record is not a history of races but ONE race plus what the projection has
## already granted on its behalf — because a base attribute grant and an affinity grant
## cannot be un-done by removing a modifier, so a rebuild needs to know what to subtract
## before it re-adds.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"race_state"
## Every stat modifier race contributes is tagged with this prefix, so a re-projection
## can strip and rebuild the whole contribution from the ledger.
const SOURCE_PREFIX := "race:"
## The `Actor.traits` mirror prefix.
const TRAIT_PREFIX := "race:"


## The stat source id one race contributes under.
static func source_for(id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, id])


## The `Actor.traits` mirror id one race is reflected under.
static func trait_for(id: StringName) -> StringName:
	return StringName("%s%s" % [TRAIT_PREFIX, id])


## True when a stat modifier source belongs to this module.
static func is_own_source(source: StringName) -> bool:
	return String(source).begins_with(SOURCE_PREFIX)


## A known-race filter for this module. `known_races` comes from the catalog; an entry
## naming content that no longer ships is dropped rather than persisted, so a save from
## a wider content build cannot smuggle in a race the current build does not define.
##
## A payload that cannot be read is diagnosed as empty, never partially applied. Half a
## ledger is worse than none: the projection subtracts what the ledger says it already
## granted, so a half-read ledger would subtract the wrong amount.
static func normalize(payload: Dictionary, known_races: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"race": "",
		"applied_race": "",
		"granted": {},
	}
	if payload.is_empty():
		return out
	var race_id := String(payload.get("race", ""))
	if race_id != "" and (known_races.is_empty() or known_races.has(race_id)):
		out["race"] = race_id
	# `applied_race` is whatever the projection last put on the actor, including one the
	# catalog no longer ships: that contribution still has to be subtracted, and a
	# dropped definition is exactly when it would otherwise be left behind. So this
	# field is deliberately NOT filtered by `known_races`.
	var applied := String(payload.get("applied_race", ""))
	if applied != "":
		out["applied_race"] = applied
	# The grant record is the race's own authored base-attribute and affinity payload,
	# kept verbatim because only the ledger knows what the actor was already given.
	# Entries are dropped when their definition has gone, since there is nothing left to
	# subtract with them.
	var granted = payload.get("granted", {})
	if granted is Dictionary:
		for race_key in (granted as Dictionary).keys():
			var key := String(race_key)
			var record = (granted as Dictionary)[race_key]
			if not (record is Dictionary):
				continue
			if not known_races.is_empty() and not known_races.has(key):
				continue
			var clean := _grant_record(record as Dictionary)
			# A grant that sanitises down to nothing is not a grant. Keeping the key
			# with empty maps would tell the projection "this actor was already given
			# something by this race" when it was given nothing, so the subtraction
			# it would perform is a no-op that still reads as a record of a grant.
			if (
				(clean["attributes"] as Dictionary).is_empty()
				and (clean["affinities"] as Dictionary).is_empty()
			):
				continue
			out["granted"][key] = clean
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## The actor's race id, or `&""` when it has none. The one question the rest of the
## module asks about identity.
static func race_id(ledger: Dictionary) -> StringName:
	return StringName(String(ledger.get("race", "")))


## The race whose contribution is currently on the actor.
static func applied_race(ledger: Dictionary) -> StringName:
	return StringName(String(ledger.get("applied_race", "")))


## One race's grant record, or an empty one when the ledger carries none for it.
static func grants(ledger: Dictionary, race_id: StringName) -> Dictionary:
	var record = (ledger.get("granted", {}) as Dictionary).get(String(race_id), {})
	return record as Dictionary if record is Dictionary else {}


static func _grant_record(record: Dictionary) -> Dictionary:
	var out := {"attributes": {}, "affinities": {}}
	var attributes = record.get("attributes", {})
	if attributes is Dictionary:
		for key in (attributes as Dictionary).keys():
			var value = (attributes as Dictionary)[key]
			if value is float or value is int:
				out["attributes"][String(key)] = float(value)
	var affinities = record.get("affinities", {})
	if affinities is Dictionary:
		for key in (affinities as Dictionary).keys():
			var value = (affinities as Dictionary)[key]
			if value is float or value is int:
				out["affinities"][String(key)] = float(value)
	return out
