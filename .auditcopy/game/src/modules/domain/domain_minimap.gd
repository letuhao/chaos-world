class_name DomainMinimap
extends RefCounted

## The domain mini map as a PRIMITIVES-ONLY payload (BL-0220).
##
## This is a read model, not a drawing. `WorldMapScreen` owns a node graph of the
## WORLD; this is a tile-space picture of one domain's interior, and the two answer
## different questions, so neither duplicates the other. What this borrows from that
## screen is the CONTRACT it follows: a screen and the headless driver read the same
## dictionary, and the test asserts the dictionary rather than pixels.
##
## The value is TIER LEGIBILITY (ADR 0073). A minimap that only shows where you have
## been is a breadcrumb trail; one that shows an `arena` promising a miniboss and a
## `core` promising a boss BEFORE anything is fought is a route planner — and it is
## readable because every marker traces back to a TAG or a ROLE on the room, never to a
## distance or a size, which is the post-hoc heuristic ADR 0073 forbids.
##
## Fog is `DomainApi.discovered`, the same durable set the facade already owns
## (api.gd:118), reached through the facade and never through module internals. A room
## the actor has not reached is not drawn: not faded, not greyed, not drawn — because
## an unvisited room shown dimly is the spoiler the fog exists to prevent.
##
## Everything emitted is a String, int, bool, Array or Dictionary. No `Vector2`, no
## `Vector2i`, no `Rect2i`, no `StringName`, no `Resource`. A payload carrying an
## engine type does not survive the JSON hop the headless driver reads it through, and
## nothing in this repo can see that until a save breaks.

## The tier a room promises. Ordinal so a consumer can sort without a name table.
enum Tier { ROOM, MINIBOSS, BOSS }

## Severity buckets for a room's environments, as primitives. ADR 0075's
## `EnvironmentZoneDef` publishes an authored 3-point band; the read model maps it to
## a low/med/high so a consumer never has to know that numbering.
const SEVERITY_BY_INTENSITY := {1: "low", 2: "med", 3: "high"}

## Marker kind per POI tag: the ONE source ADR 0073 names for the minimap POI layer.
## A tag absent here marks nothing. An unknown tag is content this build has not
## learned to draw, not a reason to invent a marker.
const POI_BY_TAG := {
	&"boss_worthy": "boss",
	&"elite_guard": "elite_guard",
	&"puzzle_formation": "puzzle",
	&"refuge": "refuge",
	&"treasure_keyed": "treasure",
}

## The tag set, in canonical order, so the published POI surface is stable and a
## consumer can enumerate it without holding a room.
const POI_TAGS: Array[StringName] = [
	&"boss_worthy",
	&"elite_guard",
	&"puzzle_formation",
	&"refuge",
	&"treasure_keyed",
]


## The minimap for the domain `actor` is in, or `{}` when there is no active domain.
static func render(actor: Actor, map: DomainMap) -> Dictionary:
	if actor == null or map == null:
		return {}
	var discovered := _discovered_set(actor)
	var rects := DomainPaths.layout(map)
	return {
		"layout": _layout(rects),
		"bounds": _bounds(rects),
		"discovered": _discovered_ids(map, discovered),
		"rooms": _rooms(map, rects, discovered),
		"pois": _pois(map, rects, discovered),
		"zones": _zones(map),
		"routes": _routes(map),
		"weather": String(map.weather),
	}


## An empty domain renders as `{}`, the repo's does-not-exist vocabulary (AGENTS.md).
## A minimap of nothing must not read like a minimap of a room with no markers.
static func summary() -> Dictionary:
	return {}


# ── internals ────────────────────────────────────────────────────────────────


## The discovered set, reached through the facade — the only surface another unit may
## touch (AGENTS.md's facade rule). An empty payload means the same thing at every
## call site, so the fallback is one rule in one place rather than a check per caller.
static func _discovered_set(actor: Actor) -> Dictionary:
	var out := {}
	var rows := DomainApi.discovered(actor)
	if not rows is Array:
		return out
	for room_id in rows:
		out[StringName(room_id)] = true
	return out


## The room ids drawn, canonical order: the discovered set the actor has earned, plus
## the entry. NOT the reachable frontier — a room the actor has never been to is not
## on the minimap however easy it would be to reach.
static func _discovered_ids(map: DomainMap, discovered: Dictionary) -> Array:
	var out: Array = []
	for room_id in map.room_ids_sorted():
		if discovered.has(room_id):
			out.append(String(room_id))
	return out


## The laid-out rects, one `[x, y, w, h]` per room. Flattened because `Rect2i` is an
## engine type and this payload has to survive `JSON.stringify` for the headless
## driver; the same rule `DomainMap.to_dict` follows for `extent`.
static func _layout(rects: Dictionary) -> Dictionary:
	var out := {}
	for key in rects.keys():
		out[String(key)] = _rect(rects[key])
	return out


static func _rooms(map: DomainMap, rects: Dictionary, discovered: Dictionary) -> Array[Dictionary]:
	var reachable := map.reachable_room_ids()
	var out: Array[Dictionary] = []
	for room_id in _discovered_ids(map, discovered):
		var room_def := map.room(room_id)
		if room_def == null:
			continue
		(
			out
			. append(
				{
					"room_id": String(room_id),
					"kind": String(room_def.kind),
					"tags": _strings(room_def.tags),
					"rect": _rect(rects.get(String(room_id), Rect2i())),
					"reachable": reachable.has(room_id),
					"discovered": discovered.has(room_id),
					"hostile": room_def.is_hostile(),
					"is_entry": room_id == map.entry_room,
					"is_core": room_def.kind == &"core",
					"tier": _tier_name(_tier_of(room_def)),
					"tier_rank": int(_tier_of(room_def)),
				}
			)
		)
	return out


static func _pois(map: DomainMap, rects: Dictionary, discovered: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in _discovered_ids(map, discovered):
		var room_def := map.room(room_id)
		if room_def == null:
			continue
		var rect: Rect2i = rects.get(String(room_id), Rect2i())
		var anchor := rect.get_center()
		# Canonical marker order, so a room's POIs read the same on every render and
		# `POI_BY_TAG`'s own ordering does not depend on how the tags were authored.
		var tags: Array[StringName] = room_def.tags.duplicate()
		tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for tag in tags:
			var marker := StringName(POI_BY_TAG.get(tag, &""))
			if marker == &"":
				continue
			(
				out
				. append(
					{
						"room_id": String(room_id),
						"tag": String(tag),
						"marker": String(marker),
						"anchor": [anchor.x, anchor.y],
						"tier": _tier_name(_tier_of(room_def)),
					}
				)
			)
	return out


## Every severe environment, flattened with its room, its authored severity and the
## levers that reduce it (ADR 0075). NOT fogged, and deliberately: what a room will do
## to you is a property of the room, and routing AROUND a hazard is only possible if
## you can see it before you are standing in it. Fearing the unknown is a different
## design from knowing where the lava is.
static func _zones(map: DomainMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in map.zones():
		(
			out
			. append(
				{
					"room_id": String(row.get("room_id", "")),
					"zone_id": String(row.get("zone_id", "")),
					"kind": String(row.get("kind", "")),
					"intensity": int(row.get("intensity", 1)),
					"severity":
					String(SEVERITY_BY_INTENSITY.get(int(row.get("intensity", 1)), "low")),
					"mitigation_tags": _strings(row.get("mitigation_tags", [])),
					"bounds": _box(row.get("bounds", [])),
				}
			)
		)
	return out


static func _routes(map: DomainMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for route in DomainPaths.routes(map):
		var points: Array = []
		for point in route.get("points", []):
			points.append(_point(point))
		out.append({"from": route.get("from", ""), "to": route.get("to", ""), "points": points})
	return out


## The union of every laid-out rect, as `[x, y, w, h]`. The extent `DomainMap`
## publishes is the GENERATOR's grid, which is `Vector2i.ZERO` on a handcrafted map —
## so a minimap sized from it would collapse for exactly the maps a player explores
## by hand. The drawn rooms are the honest bound and are always present.
static func _bounds(rects: Dictionary) -> Array:
	if rects.is_empty():
		return [0, 0, 0, 0]
	var left: int = 0
	var top: int = 0
	var right: int = 0
	var bottom: int = 0
	var seeded := false
	for key in rects.keys():
		var rect: Rect2i = rects[key]
		if not seeded:
			left = rect.position.x
			top = rect.position.y
			right = rect.end.x
			bottom = rect.end.y
			seeded = true
			continue
		left = mini(left, rect.position.x)
		top = mini(top, rect.position.y)
		right = maxi(right, rect.end.x)
		bottom = maxi(bottom, rect.end.y)
	return [left, top, right - left, bottom - top]


## What a room PROMISES. Three closed vocabularies, strongest first: the authored POI
## tag, the spawn roles (ADR 0074), then the shape's own default band
## (room_def.gd:60). A room with none of the three is `ROOM` — not a boss because it
## is deep, which is precisely the heuristic ADR 0073 rules out.
static func _tier_of(room_def: RoomDef) -> Tier:
	var tier := Tier.ROOM
	if room_def.has_tag(&"boss_worthy") or room_def.kind == &"core":
		tier = Tier.BOSS
	elif _spawns_tier(room_def) != Tier.ROOM:
		tier = _spawns_tier(room_def)
	elif room_def.has_tag(&"elite_guard") or room_def.has_tag(&"puzzle_formation"):
		tier = Tier.MINIBOSS
	elif room_def.kind == &"arena":
		tier = Tier.MINIBOSS
	return tier


## The tier its authored roster implies, or `ROOM`. A role is a TAG (ADR 0074), so
## this reads the ref's role string and never branches on a class.
static func _spawns_tier(room_def: RoomDef) -> Tier:
	var tier := Tier.ROOM
	for ref in room_def.actor_spawn_refs:
		var role := StringName(ref.get("role", ""))
		if role == DomainRoles.BOSS:
			return Tier.BOSS
		if role == DomainRoles.MINIBOSS:
			tier = Tier.MINIBOSS
	return tier


static func _tier_name(tier: Tier) -> String:
	match tier:
		Tier.BOSS:
			return "boss"
		Tier.MINIBOSS:
			return "miniboss"
		_:
			return "room"


static func _rect(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _point(point: Variant) -> Array:
	var pair := point as Array
	return [int(pair[0]), int(pair[1])] if pair.size() == 2 else [0, 0]


static func _box(bounds: Variant) -> Array:
	var box := bounds as Array
	return (
		_rect(Rect2i()) if box.size() != 4 else [int(box[0]), int(box[1]), int(box[2]), int(box[3])]
	)


static func _strings(values: Variant) -> Array:
	var out: Array = []
	if not values is Array:
		return out
	for value in values:
		out.append(String(value))
	return out
