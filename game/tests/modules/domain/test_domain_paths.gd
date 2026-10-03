extends TestCase

## The corridor/path layer: geometry that did not exist before (`DomainPaths`).
##
## Maps are built INLINE, the way `test_domain_map_contract.gd` does it, and never
## through `domain_generator.gd` — that file belongs to another agent and may be
## mid-edit, and a test that depends on it measures that agent's progress rather than
## this layer.
##
## The load-bearing claims: a corridor exists only where the map says the edge holds
## from BOTH ends, the elbow is a RULE rather than a coin flip, and every answer is a
## pure function of the map. Nothing here may be allowed to guess.

# ── fixtures ─────────────────────────────────────────────────────────────────


func _spawn(ref_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": "warden", "role": role, "count": count}


func _room(
	room_id: StringName,
	kind: StringName,
	exits: Array[StringName],
	room_size: Vector2i = Vector2i(8, 6)
) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	room.size = room_size
	return room


## A three-room line with an authored core — the shape from the contract suite, sized
## so the layout has real extents to pack. Entry is an `empty` breather: a `floor`
## defaults to the hostile `skirmish` band (room_def.gd:60), and a run that opens with
## a fight is not a run you can walk out of.
func _line_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(40, 32), 11)
	var entry := _room(&"entry_grove", &"floor", [&"ember_flue"] as Array[StringName])
	entry.roster_band = &"empty"
	entry.size = Vector2i(10, 8)
	map.add_room(entry)
	var flue := _room(
		&"ember_flue", &"corridor", [&"entry_grove", &"heart_of_ashes"] as Array[StringName]
	)
	flue.size = Vector2i(6, 14)
	map.add_room(flue)
	var core := _room(&"heart_of_ashes", &"core", [&"ember_flue"] as Array[StringName])
	core.size = Vector2i(20, 18)
	core.actor_spawn_refs = [_spawn("b1", "boss")] as Array[Dictionary]
	map.add_room(core)
	map.entry_room = &"entry_grove"
	return map


## The corridor set as unordered `"a~b"` pair keys, with each pair written in canonical
## order so a route and its reverse collapse to one key. The assertions are about WHICH
## corridors exist, not which direction a route was emitted, so comparing pairs is the
## honest shape for them.
func _pairs(routes: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for route in routes:
		var pair := [String(route["from"]), String(route["to"])]
		pair.sort()
		out["%s~%s" % [pair[0], pair[1]]] = true
	return out


## A domain with a branch, an arena and a loop, which is where a shortest-route
## question actually has an answer worth asserting: two ways to the core, and the tie
## has to break the same way every time.
func _branched_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(64, 48), 23)
	var entry := _room(&"entry", &"floor", [&"hub"] as Array[StringName])
	entry.roster_band = &"empty"
	entry.size = Vector2i(12, 10)
	map.add_room(entry)
	var hub := _room(&"hub", &"gate", [&"entry", &"west", &"east"] as Array[StringName])
	hub.size = Vector2i(8, 8)
	map.add_room(hub)
	var west := _room(&"west", &"chamber", [&"hub", &"vault"] as Array[StringName])
	west.size = Vector2i(14, 6)
	west.actor_spawn_refs = [_spawn("w1", "mob", 3)] as Array[Dictionary]
	map.add_room(west)
	var east := _room(&"east", &"arena", [&"hub", &"vault"] as Array[StringName])
	east.size = Vector2i(10, 14)
	east.tags = [&"elite_guard"] as Array[StringName]
	east.actor_spawn_refs = [_spawn("e1", "miniboss")] as Array[Dictionary]
	map.add_room(east)
	var vault := _room(&"vault", &"core", [&"west", &"east"] as Array[StringName])
	vault.size = Vector2i(16, 16)
	vault.actor_spawn_refs = [_spawn("v1", "boss")] as Array[Dictionary]
	map.add_room(vault)
	map.entry_room = &"entry"
	return map


# ── the layout rule ──────────────────────────────────────────────────────────


## ADR 0072 forbids a position on `RoomDef`, so the layout is DERIVED. The contract
## it has to keep is the one that makes it reproducible: the same rooms in a different
## insertion order lay out identically, because nothing may read dictionary order.
func test_layout_is_a_pure_function_of_the_map() -> void:
	var forward := _line_map()
	# A DIFFERENT insertion order for the same rooms: the same rooms, the same exits.
	var reordered := DomainMap.new(Vector2i(40, 32), 11)
	for room_id in [&"heart_of_ashes", &"entry_grove", &"ember_flue"]:
		reordered.add_room(forward.room(room_id))
	reordered.entry_room = forward.entry_room
	assert_eq(
		JSON.stringify(DomainPaths.layout(forward)),
		JSON.stringify(DomainPaths.layout(reordered)),
		"insertion order does not move a room"
	)
	assert_eq(
		JSON.stringify(DomainPaths.layout(_line_map())),
		JSON.stringify(DomainPaths.layout(forward)),
		"the same map twice lays out identically"
	)


## Level `n` is column `n`, and rooms in a column never overlap: the layout must be
## something a floor plan can be drawn from.
func test_layout_places_every_room_without_overlap() -> void:
	var map := _branched_map()
	var rects := DomainPaths.layout(map)
	assert_eq(rects.size(), map.room_count(), "every room is placed, orphans included")
	for left_id in map.room_ids_sorted():
		for right_id in map.room_ids_sorted():
			if left_id == right_id:
				continue
			var a: Rect2i = rects[String(left_id)]
			var b: Rect2i = rects[String(right_id)]
			assert_eq(a.intersects(b), false, "'%s' and '%s' do not overlap" % [left_id, right_id])


## A room authored with no size is a room that was never given one; it still needs a
## footprint, or every corridor into it collapses to a point.
func test_layout_gives_a_sizeless_room_a_footprint() -> void:
	var map := _line_map()
	map.room(&"ember_flue").size = Vector2i.ZERO
	var rect: Rect2i = DomainPaths.layout(map)["ember_flue"]
	assert_eq(rect.size.x >= 1 and rect.size.y >= 1, true, "a zero-size room still occupies tiles")
	for route in DomainPaths.routes(map):
		assert_eq(route["points"].size() >= 2, true, "and every corridor still has a polyline")


## Rooms the entry cannot reach are a map defect the CONTRACT reports; the layout still
## places them, because a room missing from the layout is a room a minimap omits
## silently and two consumers would then disagree about how many rooms exist.
func test_layout_places_an_unreachable_room_deterministically() -> void:
	var map := _line_map()
	map.add_room(_room(&"lost_hall", &"chamber", [] as Array[StringName], Vector2i(9, 7)))
	assert_eq(DomainPaths.layout(map).size(), 4, "the orphan is still placed")
	assert_eq(
		JSON.stringify(DomainPaths.layout(map)),
		JSON.stringify(DomainPaths.layout(map)),
		"and it lands in the same place every time"
	)


## The walk behind the layout is bounded twice over — by the cap and by the room set —
## so a graph that could not converge fails loud rather than spinning
## (docs/incidents.jsonl).
func test_the_level_walk_terminates() -> void:
	var map := _branched_map()
	map.add_room(_room(&"lost_hall", &"chamber", [] as Array[StringName], Vector2i(6, 6)))
	var placed := 0
	for room_id in map.room_ids_sorted():
		if DomainPaths.layout(map).has(String(room_id)):
			placed += 1
	assert_eq(placed, map.room_count(), "every level drained and all %d rooms placed" % placed)


# ── corridors ────────────────────────────────────────────────────────────────


## The acceptance core: no invented edges. Every route joins two rooms that each list
## the other in `exits`.
func test_every_route_endpoint_lists_the_other_as_an_exit() -> void:
	var map := _branched_map()
	for route in DomainPaths.routes(map):
		var from_def := map.room(StringName(route["from"]))
		var to_def := map.room(StringName(route["to"]))
		assert_ne(from_def, null, "'%s' is a real room" % route["from"])
		assert_ne(to_def, null, "'%s' is a real room" % route["to"])
		assert_eq(
			from_def.exits.has(to_def.room_id),
			true,
			"'%s' exits to '%s'" % [route["from"], route["to"]]
		)
		assert_eq(
			to_def.exits.has(from_def.room_id),
			true,
			"'%s' exits to '%s'" % [route["to"], route["from"]]
		)


## A corridor is a thing the player walks BOTH ways. The contract only checks an exit
## RESOLVES, so a map can carry a one-way edge; drawing geometry for one would put a
## passage on the map that is not there.
func test_a_one_way_exit_gets_no_corridor() -> void:
	var map := _line_map()
	map.room(&"ember_flue").exits.erase(&"heart_of_ashes")
	var joined: Dictionary = _pairs(DomainPaths.routes(map))
	assert_eq(joined.has("ember_flue~heart_of_ashes"), false, "no corridor for a one-way exit")
	assert_eq(joined.has("ember_flue~entry_grove"), true, "the mutual exit still has one")


## An exit pointing at a room that is not there is a defect the contract reports; the
## path layer must not invent a corridor into the void for it.
func test_a_dangling_exit_gets_no_corridor() -> void:
	var map := _line_map()
	map.room(&"entry_grove").exits.append(&"nowhere")
	var joined: Dictionary = _pairs(DomainPaths.routes(map))
	assert_eq(joined.size(), 2, "only the two real corridors")
	assert_eq(
		joined.has("nowhere~ember_flue"), false, "nothing routes into a room that is not there"
	)
	assert_eq(joined.has("nowhere~entry_grove"), false, "nor out of one")


## Symmetry under swapping the endpoints, and exactly one corridor per pair.
func test_routes_are_symmetric_and_never_duplicated() -> void:
	var map := _branched_map()
	var seen := {}
	for route in DomainPaths.routes(map):
		var key := "%s~%s" % [route["from"], route["to"]]
		assert_eq(seen.has(key), false, "one corridor per pair, '%s' is not repeated" % key)
		seen[key] = true
		assert_eq(
			String(route["from"]) < String(route["to"]),
			true,
			"a corridor is emitted in one canonical direction"
		)
		var swapped := DomainPaths.corridor(map, StringName(route["to"]), StringName(route["from"]))
		assert_ne(swapped, {}, "asking for the reversed pair finds the same corridor")
		assert_eq(
			JSON.stringify(swapped["points"]),
			JSON.stringify(route["points"]),
			"and it is the same geometry, not a different L"
		)


func test_routes_are_deterministic() -> void:
	var first := JSON.stringify(DomainPaths.routes(_branched_map()))
	var second := JSON.stringify(DomainPaths.routes(_branched_map()))
	assert_eq(first, second, "the same map twice produces identical corridors")


## An L needs two legs, so a polyline has at least two points; a degenerate point would
## be a corridor no consumer can draw.
func test_every_polyline_has_at_least_two_points() -> void:
	for map in [_line_map(), _branched_map()]:
		var rows := DomainPaths.routes(map)
		assert_eq(rows.size() > 0, true, "the fixture really has corridors")
		for route in rows:
			assert_eq(route["points"].size() >= 2, true, "a corridor has at least two points")
			for point in route["points"]:
				assert_eq(point.size(), 2, "a point is [x, y] of integers")
				assert_eq(
					point is Array and typeof(point[0]) in [TYPE_INT, TYPE_FLOAT],
					true,
					"and carries no engine type"
				)


## The elbow is the decision domain_generator.gd:24 already records: the longer leg
## leads. A tie is not a coin flip either — a zero on an axis already sends the L the
## other way — so this map gives two equal-handed runs, which a coin flip would break
## half the time.
func test_the_elbow_leads_with_the_longer_leg() -> void:
	var map := DomainMap.new(Vector2i(40, 32), 5)
	var west := _room(&"west", &"floor", [&"east"] as Array[StringName], Vector2i(4, 4))
	west.roster_band = &"empty"
	var east := _room(&"east", &"floor", [&"west"] as Array[StringName], Vector2i(4, 4))
	east.roster_band = &"empty"
	map.add_room(west)
	map.add_room(east)
	map.entry_room = &"west"
	var route: Dictionary = (DomainPaths.routes(map))[0]
	var points: Array = route["points"]
	# `west` sorts before `east`, so the corridor runs west -> east: column 0 to column
	# 1, same row, equal extents, so dx and dy are equal and the >= sends it horizontal.
	assert_eq(route["from"], "west", "canonical direction")
	assert_eq(points.size(), 2, "a straight run needs no elbow, so the L collapses to a line")
	assert_eq(int(points[0][1]), int(points[1][1]), "a horizontal run holds its row")
	assert_eq(int(points[0][0]), 3, "and leaves `west` on its right wall, facing `east`")
	assert_eq(int(points[1][0]), 6, "to enter `east` on its left wall")


## A route's points stay inside the two rooms it joins or the clearance between them.
## A corridor that starts outside its own room is the failure this pins.
func test_a_corridor_starts_inside_the_room_it_leaves() -> void:
	for map in [_line_map(), _branched_map()]:
		var rects := DomainPaths.layout(map)
		for route in DomainPaths.routes(map):
			var from_rect: Rect2i = rects[route["from"]]
			var to_rect: Rect2i = rects[route["to"]]
			var start: Array = route["points"][0]
			var end: Array = route["points"][route["points"].size() - 1]
			assert_eq(
				from_rect.has_point(Vector2i(int(start[0]), int(start[1]))),
				true,
				"'%s' leaves from inside itself" % route["from"]
			)
			assert_eq(
				to_rect.has_point(Vector2i(int(end[0]), int(end[1]))),
				true,
				"'%s' is entered inside itself" % route["to"]
			)


## The width is authored from the room KIND, not from a size or a distance, which is
## the heuristic ADR 0073 rules out. A gate or a core is entered through a mouth.
func test_corridor_width_follows_the_room_kind() -> void:
	var map := _branched_map()
	for route in DomainPaths.routes(map):
		var kinds := [
			map.room(StringName(route["from"])).kind, map.room(StringName(route["to"])).kind
		]
		var wide := kinds.has(&"gate") or kinds.has(&"core")
		assert_eq(
			route["width"],
			DomainPaths.GATE_WIDTH if wide else DomainPaths.CORRIDOR_WIDTH,
			"width follows kind %s" % str(kinds)
		)


# ── routing ──────────────────────────────────────────────────────────────────


func test_path_between_finds_a_real_route() -> void:
	var map := _line_map()
	var route := DomainPaths.path_between(map, &"entry_grove", &"heart_of_ashes")
	assert_eq(route, ["entry_grove", "ember_flue", "heart_of_ashes"] as Array[String], "the line")
	for index in range(route.size() - 1):
		var a: RoomDef = map.room(StringName(route[index]))
		var b: RoomDef = map.room(StringName(route[index + 1]))
		assert_eq(a.exits.has(b.room_id), true, "each hop is an authored exit")


## `[]` rather than a guess: a fabricated route walks a player into a wall. Covers an
## unknown room AND a room the entry cannot reach — neither has a route to find.
func test_path_between_refuses_a_pair_it_cannot_route() -> void:
	var map := _branched_map()
	map.add_room(_room(&"lost_hall", &"chamber", [] as Array[StringName], Vector2i(6, 6)))
	assert_eq(DomainPaths.path_between(map, &"nowhere", &"hub").size(), 0, "an unknown start")
	assert_eq(DomainPaths.path_between(map, &"hub", &"nowhere").size(), 0, "an unknown goal")
	assert_eq(DomainPaths.path_between(map, &"entry", &"lost_hall").size(), 0, "no route exists")
	assert_eq(DomainPaths.path_between(null, &"entry", &"hub").size(), 0, "no map, no route")
	assert_eq(DomainPaths.travel_steps(map, &"entry", &"lost_hall"), 0, "and no travel is claimed")


## Shortest wins, and the tie between two equal-length routes breaks the SAME way every
## time: the frontier is FIFO over canonically ordered exits, so the answer is a pure
## function of the map rather than of insertion order.
func test_path_between_is_shortest_and_stable() -> void:
	var map := _branched_map()
	var route := DomainPaths.path_between(map, &"entry", &"vault")
	assert_eq(route.size(), 4, "three corridors, not four")
	assert_eq(route[0], "entry", "starts where asked")
	assert_eq(route[route.size() - 1], "vault", "ends where asked")
	for attempt in range(4):
		assert_eq(
			DomainPaths.path_between(map, &"entry", &"vault"),
			route,
			"attempt %d takes the same route" % attempt
		)
	assert_eq(
		route.has("east"), true, "`east` < `west`, so the canonical frontier reaches it first"
	)


func test_path_between_to_the_room_you_are_in_is_that_room() -> void:
	assert_eq(
		DomainPaths.path_between(_line_map(), &"ember_flue", &"ember_flue"),
		["ember_flue"] as Array[String],
		"no travel is one room"
	)


func test_travel_steps_agrees_with_the_path() -> void:
	var map := _branched_map()
	for pair in [
		[&"entry", &"vault"],
		[&"hub", &"west"],
		[&"east", &"west"],
		[&"vault", &"vault"],
	]:
		var from_id: StringName = pair[0]
		var to_id: StringName = pair[1]
		var route := DomainPaths.path_between(map, from_id, to_id)
		assert_eq(
			DomainPaths.travel_steps(map, from_id, to_id),
			maxi(0, route.size() - 1),
			"'%s' -> '%s' crosses one corridor per hop" % [from_id, to_id]
		)


## Every BFS layer drains and a cyclic graph terminates: the frontier is capped at the
## room set and visits each room once, so a loop in the data cannot become a loop in
## the walk (docs/incidents.jsonl).
func test_a_cyclic_map_terminates() -> void:
	var map := _branched_map()
	map.room(&"west").exits.append(&"vault")
	map.room(&"vault").exits.append(&"hub")
	var route := DomainPaths.path_between(map, &"entry", &"west")
	assert_eq(route, ["entry", "hub", "west"] as Array[String], "still the shortest")
	assert_eq(DomainPaths.travel_steps(map, &"vault", &"entry"), 3, "and travel agrees")


# ── primitives ───────────────────────────────────────────────────────────────


func test_routes_are_json_clean_primitives() -> void:
	var rows := DomainPaths.routes(_branched_map())
	var parsed: Variant = JSON.parse_string(JSON.stringify(rows))
	assert_eq(parsed is Array, true, "routes survive a JSON round trip")
	assert_eq((parsed as Array).size(), rows.size(), "with every corridor intact")


func test_an_empty_map_has_no_routes_and_no_layout() -> void:
	assert_eq(DomainPaths.routes(null).size(), 0, "no map, no corridors")
	assert_eq(DomainPaths.routes(DomainMap.new()).size(), 0, "no rooms, no corridors")
	assert_eq(DomainPaths.layout(null).size(), 0, "no map, no layout")
	assert_eq(DomainPaths.layout(DomainMap.new()).size(), 0, "no rooms, no layout")
	assert_eq(
		DomainPaths.corridor(_line_map(), &"ember_flue", &"ember_flue"), {}, "no self corridor"
	)
