class_name DomainApi
extends RefCounted

## Public facade for the `domain` module (ADR 0072-0075).
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
##
## The module exists because `world` and `loot` are BOTH at the 12-method facade cap,
## so a domain verb cannot be added to either. `socket` set the precedent: a feature
## that outgrows a neighbour owns its own facade rather than growing one that is capped.
##
## Kept to 12 public methods. When a UI need arrives, publish the read data inside an
## existing read model rather than appending a verb.

## A domain run's state key in `actor.module_data` (ADR 0027). String-keyed and
## JSON-round-trippable; this module never writes a bespoke Actor field.
const MODULE_KEY := &"domain_run"

const STATE_VERSION := 1

const ERR_NO_ACTOR := "no_actor"
const ERR_NO_MAP := "no_map"
const ERR_UNKNOWN_ROOM := "unknown_room"
const ERR_INVALID_CONTRACT := "invalid_contract"


## Query: the active domain's map as a primitive dictionary, or `{}` when the actor is
## not in a domain. The read model every screen and the headless driver consume.
static func map_summary(actor: Actor) -> Dictionary:
	var map := _map(actor)
	if map == null:
		return {}
	var room := map.entry()
	return {
		"domain_id": String(_state(actor).get("domain_id", "")),
		"seed": map.seed,
		"extent": [map.extent.x, map.extent.y],
		"entry_room": String(map.entry_room),
		"weather": String(map.weather),
		"room_count": map.room_count(),
		"kinds": _to_strings(map.kinds_present()),
		"spawn_count": map.spawn_refs().size(),
		"zone_count": map.zones().size(),
		"reachable": map.reachable_room_ids().size(),
		"hostile_rooms": _hostile_room_count(map),
		"entry_kind": String(room.kind) if room != null else "",
	}


## Query: the whole map, canonical and JSON-clean. This is the headless driver's
## payload (BL-0220): an agent reads the domain without a display.
static func map_data(actor: Actor) -> Dictionary:
	var map := _map(actor)
	return {} if map == null else map.to_dict()


## Query: rooms as primitive dictionaries in canonical order, so a caller can render a
## floor plan or a minimap without reaching into a `RoomDef`.
static func rooms(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var map := _map(actor)
	if map == null:
		return out
	for room_id in map.room_ids_sorted():
		var entry := (map.room(room_id) as RoomDef).to_dict()
		entry["reachable"] = map.reachable_room_ids().has(room_id)
		out.append(entry)
	return out


## Query: one room, or `{}`. Null rather than a guess: a caller that silently fell
## through to the first room would place a spawn somewhere arbitrary.
static func room(actor: Actor, room_id: StringName) -> Dictionary:
	var map := _map(actor)
	if map == null or not map.has_room(room_id):
		return {}
	return (map.room(room_id) as RoomDef).to_dict()


## Query: the severe environments in the active domain, flattened, each carrying its
## owning room and its mitigation levers (ADR 0075). An empty list means the domain has
## none — never a silent default zone.
static func environment_zones(actor: Actor) -> Array[Dictionary]:
	var map := _map(actor)
	return [] if map == null else map.zones()


## Query: who is placed in the active domain, as primitives: role, inhabitant, count,
## room. A role is a tag on an `Actor`, never a class (ADR 0074).
static func population(actor: Actor) -> Array[Dictionary]:
	return [] if _map(actor) == null else (_map(actor) as DomainMap).spawn_refs()


## Query: the rooms the actor has discovered. Durable across leaving (BL-0252): the
## map remembers you even though the run does not persist.
static func discovered(actor: Actor) -> Array:
	return _state(actor).get("discovered", [])


## Query: a flat machine-readable report of the whole domain, for the headless driver
## and for tests. `{}` when the actor is not in a domain.
static func summary(actor: Actor) -> Dictionary:
	var map_summary := map_summary(actor)
	if map_summary.is_empty():
		return {}
	return {
		"map": map_summary,
		"rooms": rooms(actor).size(),
		"zones": environment_zones(actor).size(),
		"population": population(actor).size(),
		"discovered": discovered(actor).size(),
	}


## Action: enter a domain from an already-built map. The map is the producer seam's
## output (ADR 0072), so a handcrafted and a generated domain arrive identically.
##
## Refuses on an invalid map rather than entering a broken one: a run that starts in a
## map with a dangling exit is a run the player cannot finish.
static func enter(actor: Actor, map: DomainMap, domain_id: StringName = &"") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	if map == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	var problems := DomainMapContract.assert_valid(map)
	if not problems.is_empty():
		return {
			"ok": false,
			"reason": ERR_INVALID_CONTRACT,
			"problems": Array(problems),
		}
	var state := _ensure_state(actor)
	state["version"] = STATE_VERSION
	state["domain_id"] = String(domain_id)
	state["map"] = map.to_dict()
	state["discovered"] = [String(map.entry_room)]
	actor.set_module_data(MODULE_KEY, state)
	return {"ok": true, "domain_id": String(domain_id), "room_count": map.room_count()}


## Action: leave the domain. The run is discarded and the discovered set is KEPT: the
## map remembers you, the inhabitants do not (BL-0252).
static func leave(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	if _map(actor) == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	var state := _state(actor)
	var discovered: Array = state.get("discovered", [])
	state.erase("map")
	actor.set_module_data(MODULE_KEY, state)
	return {"ok": true, "discovered": discovered.size()}


## Action: record a room the actor has reached, and the domain-level weather bias.
## Weather re-weights authored zones; it never applies a status of its own (ADR 0075).
static func visit_room(actor: Actor, room_id: StringName, weather: StringName = &"") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var map := _map(actor)
	if map == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	if not map.has_room(room_id):
		return {"ok": false, "reason": ERR_UNKNOWN_ROOM, "room_id": String(room_id)}
	var state := _ensure_state(actor)
	var discovered: Array = state.get("discovered", [])
	var added := false
	if not discovered.has(String(room_id)):
		discovered.append(String(room_id))
		added = true
		discovered.sort()
		state["discovered"] = discovered
	if weather != &"":
		map.weather = weather
		state["map"] = map.to_dict()
	actor.set_module_data(MODULE_KEY, state)
	return {"ok": true, "room_id": String(room_id), "newly_discovered": added}


# ── internals ────────────────────────────────────────────────────────────────


static func _state(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return actor.get_module_data(MODULE_KEY)


static func _ensure_state(actor: Actor) -> Dictionary:
	var state := _state(actor)
	if state.is_empty():
		state = {"version": STATE_VERSION, "discovered": []}
	return state


static func _map(actor: Actor) -> DomainMap:
	var state := _state(actor)
	if state.is_empty() or not state.has("map"):
		return null
	return DomainMap.from_dict(state["map"])


static func _hostile_room_count(map: DomainMap) -> int:
	var count := 0
	for room_id in map.room_ids_sorted():
		if (map.room(room_id) as RoomDef).is_hostile():
			count += 1
	return count


static func _to_strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
