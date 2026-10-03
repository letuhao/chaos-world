class_name WorldSpawnApi
extends RefCounted

## Public facade for the `world_spawn` module. Other modules may reference ONLY
## this file (`api.gd`).
##
## ## Why this module exists at all
##
## `WorldApi` is at the twelve-method ISP cap (`tools/arch/rules.py`
## `MAX_FACADE_PUBLIC_METHODS = 12`), and the thing this module does is not a
## `world`-module concern anyway. ADR 0113 settled the durable-world-id question:
## `WorldLocationDef.location_id` IS the durable id, and "random map" is a
## **seeded, deterministic selection from an authored pool**. `WorldApi` owns the
## realm-creation ability (`WorldState`) and a raw `locations()` scan; it does
## not own where a player is. Adding a thirteenth method was not available, and
## abusing `actor.world` — the Transcendent-tier realm-creation state — would have
## stored a place on the wrong object.
##
## ## Where the answer lives
##
## `actor.module_data[WorldSpawnState.MODULE_KEY]`, folded in on every mutating
## verb. That is ADR 0027's pattern and it is why `current()` survives
## `Actor.to_dict()` / `from_dict()` with no bespoke persistence path. `core` is
## untouched: it may not be extended without an ADR, and this needed none.
##
## ## Determinism is the contract, not an implementation detail
##
## `random()` selects from a pool that is **sorted by `location_id` before the
## draw**, because `WorldApi.locations()` is a `DirAccess` scan and a directory
## walk is not a stable order. Two calls with the same seed return the same
## location; `seed_value == 0` derives the seed from the ACTOR (FNV-1a over its
## id), never from `randf()` and never from a clock (DEF-0111).

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := WorldSpawnState.MODULE_KEY

## Where a selection came from, carried on the ledger row so a reader can tell an
## authored pick from a rolled one.
const SOURCE_EXPLICIT := "explicit"
const SOURCE_RANDOM := "random"
const SOURCE_SET := "set"


## Attach the module to `actor`: normalize whatever an `Actor.from_dict` carried
## so the very first read after a load is the same shape as every other read.
## Idempotent, and safe before the player has ever been anywhere.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, WorldSpawnState.normalize(actor.get_module_data(MODULE_KEY)))


## Move `actor` to an authored location, explicitly. Refuses `no_actor` and
## `unknown_location` and names the id back, so a caller cannot quietly leave the
## player somewhere that does not exist.
static func selected(actor: Actor, location_id: StringName) -> Dictionary:
	if actor == null:
		return _refuse("no_actor", {})
	var entry := _find(actor, location_id)
	if entry.is_empty():
		return _refuse("unknown_location", {"location_id": String(location_id)})
	var state := _arrive(actor, entry, SOURCE_EXPLICIT, 0)
	return _ok(state, {"source": SOURCE_EXPLICIT})


## A seeded, deterministic pick from the authored pool, filtered by tier and
## faction (ADR 0046 tiers, ADR 0047 factions). This is the whole of ADR 0113's
## "random map": a selection among `.tres` content, never a generator.
##
## `seed_value == 0` means "the same place for the same actor", and derives the
## seed from the actor's own id rather than from `randf()` or a clock, so the
## property a test proves — two calls with one seed agree — also holds for the
## unseeded convenience path. Refuses `no_candidates` when the filters name
## nothing authored; it does NOT widen the filters to find something.
static func random(
	actor: Actor, tier: StringName = &"", faction_id: StringName = &"", seed_value: int = 0
) -> Dictionary:
	if actor == null:
		return _refuse("no_actor", {})
	var pool := catalog(actor, tier, faction_id)
	if pool.is_empty():
		return _refuse("no_candidates", {"tier": String(tier), "faction_id": String(faction_id)})
	var used := seed_value if seed_value != 0 else WorldSpawnState.seed_from_actor(actor)
	var index := WorldSpawnState.pick_index(pool.size(), used)
	if index < 0:
		return _refuse("no_candidates", {"tier": String(tier), "faction_id": String(faction_id)})
	var entry: Dictionary = pool[index]
	var state := _arrive(actor, entry, SOURCE_RANDOM, used)
	return _ok(state, {"source": SOURCE_RANDOM, "seed": used})


## The durable location the actor is at, as primitives. Survives an
## `Actor.to_dict()` / `from_dict()` round-trip because the ledger lives under
## `module_data`. An actor nobody has moved reads `located: false` — "nowhere in
## particular" is a representable state, not a failure.
static func current(actor: Actor) -> Dictionary:
	return WorldSpawnState.view(_state(actor))


## Write the ledger's location row directly, bypassing a `locations()` lookup.
## Still refuses an id the authored pool does not ship, for the same reason
## `selected` does: a durable id that no `.tres` backs is a save nobody can mount.
static func set_current(actor: Actor, location_id: StringName) -> Dictionary:
	return selected(actor, location_id)


## The candidate pool as primitives, sorted by `location_id`. This is the
## ordering `random` draws over, exposed so a panel can render the same list the
## pick was taken from — a filter that showed a different set would be lying.
static func catalog(
	actor: Actor, tier: StringName = &"", faction_id: StringName = &""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in WorldApi.locations(actor):
		if WorldSpawnState.matches(entry, tier, faction_id):
			out.append(WorldSpawnState.candidate(entry))
	out.sort_custom(_by_location_id)
	return out


## The whole read model in one call: where the actor is, and what it could
## otherwise have gone to. The candidate count is a KEY rather than a thirteenth
## verb for the reason `EventApi.summary` folded its location read in.
static func summary(actor: Actor) -> Dictionary:
	var view := WorldSpawnState.view(_state(actor))
	view["has_actor"] = actor != null
	view["actor_id"] = "" if actor == null else String(actor.id)
	view["candidate_count"] = 0 if actor == null else WorldApi.locations(actor).size()
	view["persisted"] = actor != null and actor.get_module_data(MODULE_KEY).has("version")
	return view


# --- internals ---------------------------------------------------------------


static func _by_location_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("location_id", "")) < String(b.get("location_id", ""))


## The ledger, normalized on every read so a hand-edited save cannot make a
## typed accessor lie. Read-only: persisting happens on the mutating verbs.
static func _state(actor: Actor) -> Dictionary:
	if actor == null:
		return WorldSpawnState.empty()
	return WorldSpawnState.normalize(actor.get_module_data(MODULE_KEY))


## One arrival: fold the place onto the ledger, count the visit, persist.
static func _arrive(actor: Actor, entry: Dictionary, source: String, seed_value: int) -> Dictionary:
	var state := WorldSpawnState.normalize(actor.get_module_data(MODULE_KEY))
	WorldSpawnState.place_on(state, entry, source, seed_value)
	actor.set_module_data(MODULE_KEY, state)
	return state


## The authored row for `location_id`, or `{}`. Resolved through
## `WorldApi.locations()` so the facade rule holds and no `.tres` is loaded here.
static func _find(actor: Actor, location_id: StringName) -> Dictionary:
	var wanted := String(location_id)
	for entry in WorldApi.locations(actor):
		if String(entry.get("location_id", "")) == wanted:
			return entry
	return {}


## The answer a successful selection hands back: `{ok, reason}` with the ledger
## row FOLDED IN beside them rather than carried under a `state` key.
##
## The primitives-only contract this repo holds its facades to means no
## `Dictionary` value at any depth, and a nested row breaks it — a caller would
## have to know that `answer["state"]["location_id"]` and `answer["location_id"]`
## are the same field. `current()` and `summary()` publish the row on their own,
## so nothing is lost by flattening it here.
static func _ok(state: Dictionary, detail: Dictionary) -> Dictionary:
	var out := {"ok": true, "reason": ""}
	for key in detail.keys():
		out[String(key)] = detail[key]
	var view := WorldSpawnState.view(state)
	for key in view.keys():
		out[String(key)] = view[key]
	return out


static func _refuse(reason: String, detail: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": reason}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out
