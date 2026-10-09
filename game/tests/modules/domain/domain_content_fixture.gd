class_name DomainContentFixture
extends RefCounted

## The reads the domain-content suite asserts with, over a `DomainMap` and its minted
## bodies.
##
## Extracted from `test_domain_content.gd`, which had grown past the file budget. These are
## the helpers that read ONLY a map, an actor list or a dictionary — the three that reach
## for the suite's own consts (`_template`, `_missing_shape`) and the one that reads the
## shipped rooms (`_authored_room_ids`) stayed behind, because a helper that needs the
## test's fixtures cannot leave the test.
##
## Everything here takes its input as an argument and returns primitives or arrays, so a
## suite asserts against a value rather than against this class's state.

## The authored def ids a generated map actually built, as the part of each namespaced
## room id before the `#`.
static func built_def_ids(map: DomainMap) -> Dictionary:
	var out: Dictionary = {}
	for room_id in map.room_ids_sorted():
		out[String(room_id).split("#", false)[0]] = true
	return out


## `sum(count)` over the map's refs — what the map AUTHORED, read off the map itself so
## the assertion cannot be satisfied by the thing under test.
static func expected_population(map: DomainMap) -> int:
	var total := 0
	for ref in map.spawn_refs():
		total += int(ref.get("count", 1))
	return total


## The roles a map's refs name, one entry per authored INSTANCE, in `spawn_map`'s order.
static func roles_of_refs(map: DomainMap) -> Array[String]:
	var out: Array[String] = []
	for ref in map.spawn_refs():
		var role := String(ref.get("role", ""))
		for _instance in int(ref.get("count", 1)):
			out.append(role)
	return out


## The same shape, read off the minted actors.
static func roles_of_actors(actors: Array[Actor]) -> Array[String]:
	var out: Array[String] = []
	for actor in actors:
		out.append(String(DomainSpawner.role_of(actor)))
	return out


## Whether an authored fixture carries `tag`. A `Dictionary` has no `has_tag` — that is
## `RoomDef`'s and `InhabitantDef`'s — so the membership question is asked of the
## `tags` array the shape actually defines.
static func tagged(fixture: Dictionary, tag: StringName) -> bool:
	var tags: Array = fixture.get("tags", [])
	return tags.has(tag) or tags.has(String(tag))


## The unique values in `values`, first-seen order. A bounded `for`; there is no
## `Array.uniq` in this GDScript and hand-rolling it keeps the assertion readable.
static func distinct(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


static func max_of(values: Array[float]) -> float:
	var out := 0.0
	for value in values:
		out = maxf(out, value)
	return out


static func min_of(values: Array[float]) -> float:
	var out := INF
	for value in values:
		out = minf(out, value)
	return out
