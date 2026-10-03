class_name DomainPaths
extends RefCounted

## Corridor GEOMETRY for a `DomainMap`, derived entirely from what the map already
## says. Before this file a domain had adjacency (`RoomDef.exits`) but no corridors —
## the dead `CORNER_TIE` at domain_generator.gd:54 is the scar of a plan that shipped
## half. A screen could list rooms and nothing could connect them.
##
## ## Why a layout has to be invented, and why it is still reproducible
##
## ADR 0072 keeps `DomainMap` engine-agnostic: no `Node`, no `TileMap`, `Vector2i`
## only, and NO position field on a room (domain_map.gd:20 says so). So there is
## nothing to read a position from and nothing this file is permitted to add. Rooms
## are therefore LAID OUT here, from their own `size` and the exit graph, by a rule
## that is a pure function of the map — same rooms, same sizes, same exits, same
## coordinates, on every machine and every run.
##
## ## The layout rule
##
## 1. Rooms are grouped into BREADTH-FIRST LEVELS from `entry_room` over `exits`,
##    with exits visited in canonical room-id order, so the level a room lands in is
##    a property of the graph rather than of dictionary insertion order.
## 2. Level `n` is COLUMN `n`: its rooms stack downward from `y = 0`, in canonical
##    order, each one tile-extent tall plus `TILE_GAP` of clearance. A room's `size`
##    gives its extent; a `size` of zero is a room that was never authored with one
##    and still needs a footprint, so it resolves to `MIN_ROOM_TILES` rather than
##    collapsing to nothing and making every corridor between it degenerate.
## 3. The next column starts one gap past the widest room in the previous column.
## 4. Rooms the entry cannot reach go in one final column, in canonical order. They
##    are a map defect `DomainMapContract` reports separately; the layout still has
##    to place them deterministically rather than drop them, or two consumers of the
##    same map would disagree about how many rooms exist.
##
## ## A corridor exists only when the map says so from BOTH sides
##
## `RoomDef.exits` is authored per room and the contract only checks that a target
## RESOLVES, so a map can hold a one-way exit. Geometry is not invented for one: a
## corridor is a physical thing the player walks both ways, and drawing one for an
## edge one room alone claims would put a passage on the map that does not exist.
## Every route therefore requires `a.exits.has(b)` AND `b.exits.has(a)`, and is
## emitted once, in canonical direction (`from` < `to` by room id), so the corridor
## set is symmetric under swapping the endpoints.
##
## ## The elbow is a rule, never a coin flip
##
## An L has two shapes and one of them is always the longer leg, so the choice
## cannot be random: `abs(dx) >= abs(dy)` runs horizontal first, which is the
## decision domain_generator.gd:24 already records. The same rule decides both the
## first leg and the point each room is entered through, so the polyline always
## leaves a room through a face that room actually presents to the other.
##
## Bounded everywhere: a breadth-first walk is capped by `MAX_BFS_VISITS` and capped
## again by the room set, and a polyline is built from a fixed three-tile candidate
## list. No retry, no unbounded loop (AGENTS.md's third ceiling).

## Rooms are separated by this many tiles of clearance, so no two laid-out rects
## touch and a corridor always has room to run.
const TILE_GAP := 2

## A room authored with no `size` still needs one tile to occupy. Zero would make
## every corridor into it a degenerate point.
const MIN_ROOM_TILES := 1

## A domain map is a level, not a dungeon of 128 rooms; the cap exists because a
## walk that failed to converge is a defect, not a workload (docs/incidents.jsonl,
## INC-0004/INC-0005). It names the condition: the frontier did not drain.
const MAX_BFS_VISITS := 128

## The corridor's default width, in tiles.
const CORRIDOR_WIDTH := 1

## A `gate` or a `core` is entered through a mouth rather than a crack.
const GATE_WIDTH := 2

## The room kinds whose rooms are entered through a wide mouth. Branching on KIND is
## legal and branching on size or distance from the core is not (room_def.gd:9,
## ADR 0073), so this is the closed kind set and nothing else.
const WIDE_MOUTH_KINDS: Array[StringName] = [&"gate", &"core"]


## Every corridor in the map as `{from, to, points: Array[[x, y]], width}`, in
## canonical order. Primitives only, so the headless driver (BL-0220) and a screen
## read the identical thing.
static func routes(map: DomainMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null:
		return out
	var rects := layout(map)
	# Every mutual edge, found ONCE. Iterating the exits would need a `from < to` test to
	# emit an unordered pair in one direction, and GDScript compares `StringName` by
	# hash, so `<` is not lexicographic and the same pair would flip direction between
	# runs. Skipping the pair when it has already been emitted is direction-agnostic,
	# and the room iteration is already in canonical order.
	var seen := {}
	for room_id in map.room_ids_sorted():
		var room_def := map.room(room_id)
		if room_def == null:
			continue
		for exit_id in _exits_of(map, room_def):
			var pair := _pair_key(room_id, exit_id)
			if seen.has(pair):
				continue
			seen[pair] = true
			if not _connects_both_ways(map, room_id, exit_id):
				continue
			out.append(_corridor(map, room_id, exit_id, rects))
	return out


## The corridor joining two rooms, or `{}`. Reads `routes` rather than rebuilding it,
## so a single-pair answer can never disagree with the full list.
static func corridor(map: DomainMap, from_id: StringName, to_id: StringName) -> Dictionary:
	if map == null or from_id == to_id:
		return {}
	var wanted := _pair_key(from_id, to_id)
	for route in routes(map):
		if _pair_key(StringName(route["from"]), StringName(route["to"])) == wanted:
			return route
	return {}


## The shortest room route from one room to another as room ids, both ends included,
## or `[]` when either end is not a room or no route connects them. `[]` rather than a
## guess: a caller handed a fabricated route would walk a player into a wall.
static func path_between(map: DomainMap, from_id: StringName, to_id: StringName) -> Array[String]:
	var out: Array[String] = []
	if map == null or not map.has_room(from_id) or not map.has_room(to_id):
		return out
	if from_id == to_id:
		out.append(String(from_id))
		return out
	var visited := {from_id: true}
	var parents := {}
	var frontier: Array = [from_id]
	var visits := 0
	while not frontier.is_empty() and visits < MAX_BFS_VISITS:
		visits += 1
		var room_id: StringName = frontier.pop_front()
		if room_id == to_id:
			return _rebuild(parents, from_id, to_id)
		var room_def := map.room(room_id)
		if room_def == null:
			continue
		# Canonical exits enqueued in order over a FIFO frontier, so among equally
		# short routes the answer is the same one on every run.
		for exit_id in _exits_of(map, room_def):
			if visited.has(exit_id):
				continue
			visited[exit_id] = true
			parents[exit_id] = room_id
			frontier.append(exit_id)
	return out


## How many corridors a route from `from_id` to `to_id` crosses. Zero for an
## unreachable pair and zero for the room you are already standing in: "no travel
## required" and "no route exists" are the same number, and the caller distinguishes
## them with `path_between`, which is the call that can actually tell.
static func travel_steps(map: DomainMap, from_id: StringName, to_id: StringName) -> int:
	return maxi(0, path_between(map, from_id, to_id).size() - 1)


## Every room's laid-out rect in TILES, keyed by its room id as a `String`.
## The single layout rule in the repo: `DomainMinimap` reads this rather than
## laying rooms out a second time, because two layouts is one too many.
static func layout(map: DomainMap) -> Dictionary:
	var out := {}
	if map == null:
		return out
	var column_x := 0
	for level in _levels(map):
		var row_y := 0
		var column_width := 0
		for room_id in level:
			var room_size := _room_size(map.room(room_id))
			out[String(room_id)] = Rect2i(column_x, row_y, room_size.x, room_size.y)
			row_y += room_size.y + TILE_GAP
			column_width = maxi(column_width, room_size.x)
		column_x += column_width + TILE_GAP
	return out


# ── internals ────────────────────────────────────────────────────────────────


## BFS levels from the entry, each canonically ordered. Rooms the entry cannot reach
## land in one trailing overflow level rather than being dropped: a room absent from
## the layout is a room a minimap silently omits.
static func _levels(map: DomainMap) -> Array:
	var levels: Array = []
	var placed := {}
	var frontier: Array = []
	if map.entry_room != &"" and map.has_room(map.entry_room):
		frontier.append(map.entry_room)
		placed[map.entry_room] = true
	while not frontier.is_empty():
		var visits := 0
		var level: Array = []
		var next_frontier: Array = []
		while not frontier.is_empty() and visits < MAX_BFS_VISITS:
			visits += 1
			var room_id: StringName = frontier.pop_back()
			level.append(room_id)
			var room_def := map.room(room_id)
			if room_def == null:
				continue
			for exit_id in _exits_of(map, room_def):
				if placed.has(exit_id):
					continue
				placed[exit_id] = true
				next_frontier.append(exit_id)
		level.sort_custom(_canonical)
		levels.append(level)
		frontier = next_frontier
	var orphans: Array = []
	for room_id in map.room_ids_sorted():
		if not placed.has(room_id):
			orphans.append(room_id)
	if not orphans.is_empty():
		levels.append(orphans)
	return levels


## The parent chain back to the start, reversed. Capped for the same reason the walk
## is: the chain is built from a BFS tree, so it is finite, and the cap names the
## condition that failed to hold — the chain never reached the start.
static func _rebuild(parents: Dictionary, from_id: StringName, to_id: StringName) -> Array[String]:
	# Seeded with the DESTINATION: the loop walks parents, which are strictly earlier
	# rooms, so an unseeded chain would stop one room short and report a route that does
	# not arrive.
	var chain: Array[String] = [String(to_id)]
	var cursor := to_id
	var steps := 0
	while cursor != from_id and steps < MAX_BFS_VISITS:
		steps += 1
		cursor = parents.get(cursor, &"")
		if cursor == &"":
			return []
		chain.append(String(cursor))
	chain.reverse()
	return chain


## One corridor row. Both rooms come from the map, so `layout` has already placed
## both and there is no geometry to invent or to refuse.
static func _corridor(
	map: DomainMap, from_id: StringName, to_id: StringName, rects: Dictionary
) -> Dictionary:
	return {
		"from": String(from_id),
		"to": String(to_id),
		"points": _polyline(rects[String(from_id)], rects[String(to_id)]),
		"width": _width_for(map.room(from_id), map.room(to_id)),
	}


## The pair `{a, b}` as ONE key, order-agnostic. Sorting by STRING, never by
## `StringName`: GDScript compares `StringName` by hash, so a `<` on two of them is not
## lexicographic and the same edge would key differently from run to run.
static func _pair_key(a: StringName, b: StringName) -> String:
	var one := String(a)
	var other := String(b)
	return "%s|%s" % [one, other] if one < other else "%s|%s" % [other, one]


## An L between two rects: the tile it leaves the first room by, the tile it enters
## the second through, and the elbow that joins them. Three candidates, so the work is
## bounded by three.
static func _polyline(from_rect: Rect2i, to_rect: Rect2i) -> Array:
	var from_center := from_rect.get_center()
	var to_center := to_rect.get_center()
	var dx := absi(to_center.x - from_center.x)
	var dy := absi(to_center.y - from_center.y)
	# domain_generator.gd:24 — the longer leg leads, never a coin flip. A zero on an
	# axis already sends the L the other way, so the tie needs no special case.
	var horizontal_first := dx >= dy
	var first := _mouth(from_rect, to_center, horizontal_first)
	var second := _mouth(to_rect, from_center, horizontal_first)
	var elbow := Vector2i(second.x, first.y) if horizontal_first else Vector2i(first.x, second.y)
	return _compact([[first.x, first.y], [elbow.x, elbow.y], [second.x, second.y]])


## The tile a corridor leaves `rect` through. The first leg the elbow rule chose, but
## never off a face the two rooms do not actually present to each other: rooms stacked
## in one column share an x range, so the only mouth facing the other is the vertical
## one, and leaving through a side wall would start the corridor outside its room.
static func _mouth(rect: Rect2i, toward: Vector2i, horizontal_first: bool) -> Vector2i:
	var center := rect.get_center()
	var left := rect.position.x
	var right := rect.end.x - 1
	var top := rect.position.y
	var bottom := rect.end.y - 1
	var dx := toward.x - center.x
	var dy := toward.y - center.y
	if horizontal_first and dx != 0:
		return Vector2i(right if dx > 0 else left, clampi(center.y, top, bottom))
	if dy != 0:
		return Vector2i(clampi(center.x, left, right), bottom if dy > 0 else top)
	return Vector2i(right if dx > 0 else left, clampi(center.y, top, bottom))


## Drop a point identical to its predecessor. A straight run through the elbow rule is
## two tiles, not three, and a polyline repeating a tile is an artifact no consumer can
## justify. Never shorter than two: a corridor joins two rooms, and a polyline that
## cannot describe the join is not a polyline.
static func _compact(points: Array) -> Array:
	var out: Array = []
	for point in points:
		if out.is_empty() or out[out.size() - 1] != point:
			out.append(point)
	if out.size() < 2:
		out.append(points[points.size() - 1])
	return out


static func _width_for(from_def: RoomDef, to_def: RoomDef) -> int:
	if _is_wide(from_def) or _is_wide(to_def):
		return GATE_WIDTH
	return CORRIDOR_WIDTH


static func _is_wide(room_def: RoomDef) -> bool:
	return room_def != null and WIDE_MOUTH_KINDS.has(room_def.kind)


## A corridor only exists where the map confirms the edge from BOTH ends.
static func _connects_both_ways(map: DomainMap, from_id: StringName, to_id: StringName) -> bool:
	var from_def := map.room(from_id)
	var to_def := map.room(to_id)
	if from_def == null or to_def == null:
		return false
	return from_def.exits.has(to_id) and to_def.exits.has(from_id)


## `RoomDef.exits` that resolve to a real room, canonically ordered.
static func _exits_of(map: DomainMap, room_def: RoomDef) -> Array[StringName]:
	var out: Array[StringName] = []
	if room_def == null:
		return out
	for exit_id in room_def.exits:
		if map.has_room(exit_id):
			out.append(exit_id)
	out.sort_custom(_canonical)
	return out


static func _room_size(room_def: RoomDef) -> Vector2i:
	if room_def == null:
		return Vector2i(MIN_ROOM_TILES, MIN_ROOM_TILES)
	return Vector2i(maxi(MIN_ROOM_TILES, room_def.size.x), maxi(MIN_ROOM_TILES, room_def.size.y))


static func _canonical(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
