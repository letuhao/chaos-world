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
const ERR_NO_TEMPLATE := "no_such_template"
const ERR_GENERATION_REFUSED := "generation_refused"

## Where the authored domain content lives. Deliberately under `game/src/data/`, not
## `game/data/`: `tools data audit` scans `game/data` (DATA_ROOT in tools/data.py) and
## the 160 legacy `DomainDef` records there are a DIFFERENT, older content set. Keeping
## the two apart stops the audit from grading defs it cannot cross-reference.
const TEMPLATE_DIR := "res://src/data/domains/templates"
const INHABITANT_DIR := "res://src/data/domains/inhabitants"


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


## Query: the authored domain templates, as primitives, canonical order. This is the
## CONTENT CATALOGUE: it answers "which domains exist and what shape are they" without
## generating anything, so a map screen or an agent can list what is authored before it
## commits to a seed.
##
## Lives on the facade rather than behind `DomainGenerator` because listing content and
## building a map are different questions, and only the second needs the generator.
static func templates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir == null:
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var template := load("%s/%s" % [TEMPLATE_DIR, name]) as DomainTemplateDef
		if template == null:
			continue
		(
			out
			. append(
				{
					"template_id": String(template.template_id),
					"display_name": template.display_name,
					"rooms_in_pool": template.room_pool.size(),
					"pins": template.pins.size(),
					"min_rooms": template.min_rooms,
					"max_rooms": template.max_rooms,
					"path": "%s/%s" % [TEMPLATE_DIR, name],
				}
			)
		)
	return out


## Action: generate a domain from an authored template and enter it. This is the ONE
## production entry point into a domain, and it closes the chain that was severed at
## `LootApi.enter_domain` (BL-0394): template -> DomainMap -> contract -> active run.
##
## A template that cannot produce a contract-valid map is REFUSED BY NAME rather than
## entered: a run that starts in a broken map is a run the player cannot finish.
static func generate_and_enter(
	actor: Actor, template_id: StringName, seed_value: int = 0
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var template := _template(template_id)
	if template == null:
		return {"ok": false, "reason": ERR_NO_TEMPLATE, "template_id": String(template_id)}
	var map := DomainGenerator.generate(template, seed_value)
	if map == null:
		# The generator has already push_error'd with the template, seed, condition and
		# numbers; repeating it here would add a second, vaguer message.
		return {"ok": false, "reason": ERR_GENERATION_REFUSED, "template_id": String(template_id)}
	return enter(actor, map, template_id)


static func _template(template_id: StringName) -> DomainTemplateDef:
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var template := load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef
			if template != null and template.template_id == template_id:
				dir.list_dir_end()
				return template
		file_name = dir.get_next()
	dir.list_dir_end()
	return null


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
##
## Carries the FULL map under `map_data`, not just the shape summary: the driver has to
## render the domain from this one dictionary, so it needs the rooms and corridors, not
## only the counts. Folding it in here rather than exposing a second verb is what keeps
## the facade inside the 12-method cap.
##
## `fixtures` is folded in for the same reason and because `DomainFixtures` has THREE
## separate verbs (arm / attempt / claim) with no room for a fourth: a reader that can
## call neither needs the whole fixture state here to draw the telegraph.
static func summary(actor: Actor) -> Dictionary:
	var shape := map_summary(actor)
	if shape.is_empty():
		return {}
	return {
		"map": shape,
		"map_data": _map_data(actor),
		"rooms": rooms(actor).size(),
		"zones": environment_zones(actor).size(),
		"population": population(actor).size(),
		"discovered": discovered(actor).size(),
		"fixtures": DomainFixtures.summary(actor),
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
	# A trap's `spent` flag is RUN state, so a fresh run arms every trap again rather
	# than inheriting the last one's spent ledger. Cleared here and only here: `leave`
	# discards the whole state, so a second clear would be the same line twice.
	# (`DomainFixtures.STATE_KEY` — nested, not a sibling, so `leave` reclaims it.)
	state.erase(DomainFixtures.STATE_KEY)
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


## The whole map, canonical and JSON-clean. PRIVATE and folded into `summary()` rather
## than exposed: the facade is at its 12-method cap, and the driver reads the map through
## `summary()["map_data"]`, so a thirteenth verb would buy nothing.
static func _map_data(actor: Actor) -> Dictionary:
	var map := _map(actor)
	return {} if map == null else map.to_dict()


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
