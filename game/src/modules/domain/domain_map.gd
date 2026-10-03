class_name DomainMap
extends RefCounted

## The single description of a domain's SHAPE (ADR 0072).
##
## Engine-agnostic on purpose: no `Node`, no `TileMap`, no `Vector2`. A `DomainScene`
## realizes this for play, but no gameplay rule reads a node, so the map is testable
## without a scene tree — which is what makes the acceptance criteria unit tests.
##
## **There is deliberately no `producer` / `template_id` / `layout` field.** ADR 0072
## says nothing downstream can tell whether a map was handcrafted or generated, and a
## provenance field would make that literally false. Provenance lives in the test, not
## in the data.
##
## Ordering is canonical everywhere: rooms by `room_id`, exits sorted, spawn refs by
## their ref id. GDScript dictionaries are insertion-ordered, so sorting on output is
## what makes "the same seed produces a byte-identical map" an actual claim.

const SCHEMA_VERSION := 1

## The grid a generated map occupies, in TILES.
var extent: Vector2i = Vector2i.ZERO

## Realized rooms, keyed by their map-unique `room_id`.
var rooms: Dictionary = {}

## The room a run begins in. A map with no entry is not enterable.
var entry_room: StringName = &""

## The seed this map was generated from, or 0 for a handcrafted map that is read
## rather than rolled.
var seed: int = 0

## Domain-level weather bias (ADR 0075). It re-weights which authored zones are active;
## it never applies a status of its own and never invents a zone.
var weather: StringName = &""


func _init(p_extent: Vector2i = Vector2i.ZERO, p_seed: int = 0) -> void:
	extent = p_extent
	seed = p_seed


func room_count() -> int:
	return rooms.size()


func has_room(room_id: StringName) -> bool:
	return rooms.has(room_id)


## The room, or null. Null rather than a guess: a caller that silently fell through to
## the first room would place a spawn somewhere arbitrary.
func room(room_id: StringName) -> RoomDef:
	return rooms.get(room_id, null)


func entry() -> RoomDef:
	return room(entry_room)


func add_room(room_def: RoomDef) -> void:
	rooms[room_def.room_id] = room_def


## Room ids in canonical order. Every traversal, every validator walk and every
## serialized payload goes through here, so ordering is one rule in one place.
func room_ids_sorted() -> Array[StringName]:
	var ids: Array[StringName] = []
	for room_id in rooms.keys():
		ids.append(room_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Room ids reachable from the entry under the exit graph. Breadth-first over a
## canonically ordered frontier, so the result is a pure function of the map.
func reachable_room_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	if entry_room == &"" or not rooms.has(entry_room):
		return []
	var frontier: Array[StringName] = [entry_room]
	seen[entry_room] = true
	while not frontier.is_empty():
		var current: StringName = frontier.pop_front()
		var room_def := room(current)
		if room_def == null:
			continue
		for exit_id in room_def.exits:
			if seen.has(exit_id) or not rooms.has(exit_id):
				continue
			seen[exit_id] = true
			frontier.append(exit_id)
	var ids: Array[StringName] = []
	for room_id in seen.keys():
		ids.append(room_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Every room kind present, canonical order. A map reads as a mix of shapes, and this
## is how a caller asks "does this domain have an arena?" without walking it.
func kinds_present() -> Array[StringName]:
	var found: Dictionary = {}
	for room_id in rooms.keys():
		found[rooms[room_id].kind] = true
	var kinds: Array[StringName] = []
	for kind in found.keys():
		kinds.append(kind)
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return kinds


## Every actor spawn ref in the map, as `{room_id, ref_id, inhabitant_id, role}`, in
## canonical order. `role` is a TAG on the spawned Actor, never a class (ADR 0074).
func spawn_refs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in room_ids_sorted():
		var room_def: RoomDef = rooms[room_id]
		var refs: Array = room_def.actor_spawn_refs.duplicate()
		refs.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("ref_id", "")) < String(b.get("ref_id", ""))
		)
		for ref in refs:
			(
				out
				. append(
					{
						"room_id": String(room_id),
						"ref_id": String(ref.get("ref_id", "")),
						"inhabitant_id": String(ref.get("inhabitant_id", "")),
						"role": String(ref.get("role", "")),
						"count": int(ref.get("count", 1)),
					}
				)
			)
	return out


## Every severe environment in the map, flattened, canonical order. Weather is NOT
## included: it biases these, it is not itself a zone.
func zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in room_ids_sorted():
		var room_def: RoomDef = rooms[room_id]
		for zone in room_def.environment_zones:
			var entry: Dictionary = zone.to_dict()
			entry["room_id"] = String(room_id)
			out.append(entry)
	return out


func to_dict() -> Dictionary:
	var rooms_out: Array = []
	for room_id in room_ids_sorted():
		rooms_out.append(rooms[room_id].to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"extent": [extent.x, extent.y],
		"seed": seed,
		"entry_room": String(entry_room),
		"weather": String(weather),
		"rooms": rooms_out,
	}


static func from_dict(data: Dictionary) -> DomainMap:
	var box: Array = data.get("extent", [0, 0])
	var map := DomainMap.new(
		Vector2i(int(box[0]), int(box[1])) if box.size() == 2 else Vector2i.ZERO,
		int(data.get("seed", 0))
	)
	map.entry_room = StringName(data.get("entry_room", ""))
	map.weather = StringName(data.get("weather", ""))
	for room_data in data.get("rooms", []):
		var room_def := RoomDef.from_dict(room_data)
		map.add_room(room_def)
	return map
