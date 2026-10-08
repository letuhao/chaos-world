class_name WorldSpawnState
extends RefCounted

## The durable-location ledger for the `world_spawn` module (ADR 0113).
##
## ## One stable string, and nothing else
##
## ADR 0113: "`WorldLocationDef.location_id` IS the durable world/region id." The
## player is *at* an authored location; they never carry a generated world id.
## So this ledger's load-bearing row is a plain `String` copied out of a `.tres`,
## and everything else here is the denormalised read model a panel wants without
## re-scanning `res://data/world/locations`.
##
## ## "Random map" is a SELECTION, never a generator
##
## `pick_index` is the whole of the randomness: a seeded draw over an index into
## an already-authored, already-sorted pool. Nothing in this file creates a place.
## ADR 0113 rejected procedural generation of the playfield outright.
##
## ## Why the seed is derived from the ACTOR
##
## A caller that passes `seed_value == 0` has asked for "the same place for the
## same player", not for a dice roll. So the fallback seed is a hash of the
## actor's own id — never `randf()`, never `Time.get_ticks*` (ADR 0076's
## injected-rng convention, DEF-0111's no-clock rule). A second `random` call for
## that actor lands on the same location, which is what makes a save/load pair
## reproducible.

## The `actor.module_data` key this ledger persists under (ADR 0027).
const MODULE_KEY := &"world_spawn_state"
const SCHEMA_VERSION := 1

## FNV-1a offset basis, kept as a named constant so the seed derivation reads as
## a chosen algorithm rather than a magic number.
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
## Godot treats `rng.seed = 0` as "randomise". The derivation masks into 32 bits
## and can legitimately land on zero, so a zero seed is displaced before it ever
## reaches the generator — otherwise "seed 0" would silently mean "unseeded".
const SEED_FLOOR := 0x9E3779B9


## The ledger skeleton, authored in exactly one place so a new key cannot be
## half-written. String keys throughout: `Actor.to_dict` converts only the OUTER
## `module_data` key.
static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"location_id": "",
		"display_name": "",
		"tier": "",
		"faction_id": "",
		"danger_level": 0,
		"resources": [],
		"inhabitants": [],
		"seed": 0,
		"visits": 0,
		"source": "",
	}


## Fold any payload into the current shape. A save is untrusted input, so every
## field is coerced rather than assumed: a hand-edited location id must not make
## `summary()` answer a non-primitive.
static func normalize(data: Variant) -> Dictionary:
	var out := empty()
	if not data is Dictionary:
		return out
	var source := data as Dictionary
	out["location_id"] = _text(source.get("location_id", ""))
	out["display_name"] = _text(source.get("display_name", ""))
	out["tier"] = _text(source.get("tier", ""))
	out["faction_id"] = _text(source.get("faction_id", ""))
	out["danger_level"] = maxi(0, int(source.get("danger_level", 0)))
	out["resources"] = _string_list(source.get("resources", []))
	out["inhabitants"] = _string_list(source.get("inhabitants", []))
	out["seed"] = int(source.get("seed", 0))
	out["visits"] = maxi(0, int(source.get("visits", 0)))
	out["source"] = _text(source.get("source", ""))
	return out


## The stable seed for an actor. Deterministic across runs and processes:
## Godot's built-in `String.hash()` is not the thing being relied on here, so a
## reimplementation of FNV-1a keeps the guarantee owned by this file.
##
## Returns 0 for a null actor — the caller has already refused by then, and a
## zero would mean "unseeded" if it ever leaked.
static func seed_from_actor(actor: Actor) -> int:
	if actor == null:
		return 0
	var text := "%s:%d" % [String(actor.id), SCHEMA_VERSION]  # i18n:off — a hash input
	var hashed := FNV_OFFSET
	for index in text.length():
		hashed = (hashed ^ text.unicode_at(index)) & 0xFFFFFFFF
		hashed = (hashed * FNV_PRIME) & 0xFFFFFFFF
	return maxi(1, hashed)


## The index a given seed draws out of a pool of `pool_size` candidates.
##
## The pool MUST already be in a stable order before this is called; a
## `DirAccess` scan is not stable, so the caller sorts by `location_id` first.
## Returned -1 for an empty pool rather than guessing, which is the caller's
## refusal `no_candidates`.
static func pick_index(pool_size: int, seed_value: int) -> int:
	if pool_size <= 0:
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else SEED_FLOOR
	return rng.randi_range(0, pool_size - 1)


## Whether `entry` — one row of `WorldApi.locations()` — passes the filters. An
## empty filter matches everything, so a caller asking for "anywhere" gets the
## whole pool and a caller naming a tier gets exactly that tier.
static func matches(entry: Dictionary, tier: StringName, faction_id: StringName) -> bool:
	if tier != &"" and StringName(entry.get("tier", &"")) != tier:
		return false
	if faction_id != &"" and StringName(entry.get("faction_id", &"")) != faction_id:
		return false
	return true


## One candidate row as primitives. `Array[Dictionary]` in, primitives out: no
## `WorldLocationDef` crosses this boundary.
##
## The `tier` / `faction_id` reads go through `_text` because `WorldApi.locations`
## hands back a raw `StringName` typed field, and `String(a_string_name)` is a
## runtime "Nonexistent 'String' constructor" in Godot 4 rather than a coercion.
static func candidate(entry: Dictionary) -> Dictionary:
	return {
		"location_id": _text(entry.get("location_id", "")),
		"display_name": _text(entry.get("display_name", "")),
		"tier": _text(entry.get("tier", "")),
		"faction_id": _text(entry.get("faction_id", "")),
		"danger_level": int(entry.get("danger_level", 0)),
		"resources": _string_list(entry.get("resources", [])),
		"inhabitants": _string_list(entry.get("inhabitant_types", [])),
	}


## Fold a candidate row onto the ledger, leaving `seed` / `visits` / `source` to
## the caller — those are facts about the ARRIVAL, not about the place.
static func place_on(
	state: Dictionary, entry: Dictionary, source: String, seed_value: int
) -> Dictionary:
	state["location_id"] = _text(entry.get("location_id", ""))
	state["display_name"] = _text(entry.get("display_name", ""))
	state["tier"] = _text(entry.get("tier", ""))
	state["faction_id"] = _text(entry.get("faction_id", ""))
	state["danger_level"] = int(entry.get("danger_level", 0))
	state["resources"] = _string_list(entry.get("resources", []))
	state["inhabitants"] = _string_list(entry.get("inhabitant_types", []))
	state["seed"] = seed_value
	state["source"] = source
	state["visits"] = maxi(0, int(state.get("visits", 0))) + 1
	return state


## The read model: where the actor is, and whether that is a real place.
static func view(state: Dictionary) -> Dictionary:
	return {
		"located": String(state.get("location_id", "")) != "",
		"location_id": String(state.get("location_id", "")),
		"display_name": String(state.get("display_name", "")),
		"tier": String(state.get("tier", "")),
		"faction_id": String(state.get("faction_id", "")),
		"danger_level": int(state.get("danger_level", 0)),
		"resources": _string_list(state.get("resources", [])).duplicate(),
		"inhabitants": _string_list(state.get("inhabitants", [])).duplicate(),
		"seed": int(state.get("seed", 0)),
		"visits": int(state.get("visits", 0)),
		"source": String(state.get("source", "")),
	}


static func _string_list(values: Variant) -> Array:
	var out: Array = []
	if not values is Array:
		return out
	for value in values as Array:
		out.append(_text(value))
	return out


## A `StringName`'s text, and an empty string for anything else.
##
## ## Why not `String(value)`
##
## In Godot 4 `String` is a type annotation, not a constructor with a Variant
## argument: `String(42)` raises "Nonexistent 'String' constructor" at RUNTIME,
## and the call site compiles cleanly. So the coercion the untrusted-save path
## exists to perform was the one operation that could not be performed. This
## branches on the two types a saved id can actually arrive as.
static func _text(value: Variant) -> String:
	if value is String:
		return value as String
	if value is StringName:
		return String(value as StringName)
	return ""
