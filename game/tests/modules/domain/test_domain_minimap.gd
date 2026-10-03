extends TestCase

## The domain mini map read model (`DomainMinimap`, BL-0220).
##
## Maps are built INLINE rather than through `domain_generator.gd` — that file
## belongs to another agent, and a suite that depends on it measures their progress
## instead of this read model.
##
## The claims worth pinning are the ones a drawing would hide: fog is DISCOVERY and
## not reachability, every POI traces back to a tag on the room it is drawn on, the
## tier a room advertises comes from authored content rather than from how deep it
## is, and the whole payload survives the JSON hop the headless driver reads it
## through.

# ── fixtures ─────────────────────────────────────────────────────────────────


func _spawn(ref_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": "warden", "role": role, "count": count}


func _room(
	room_id: StringName,
	kind: StringName,
	exits: Array[StringName],
	room_tags: Array[StringName] = [] as Array[StringName]
) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	room.tags = room_tags
	room.size = Vector2i(10, 8)
	return room


func _zone(zone_id: StringName, kind: StringName, intensity: int) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = zone_id
	zone.kind = kind
	zone.intensity = intensity
	zone.status_id = &"env_scourge"
	zone.mitigation_tags = [&"gear", &"affinity"] as Array[StringName]
	zone.bounds = Rect2i(2, 3, 4, 5)
	return zone


## One room of every tier promise the minimap is meant to make legible, plus a refuge
## and a treasure so the POI layer has all five tags to derive.
func _tiered_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(48, 36), 77)
	var entry := _room(&"entry", &"floor", [&"rest"] as Array[StringName])
	entry.roster_band = &"empty"
	entry.tags = [&"refuge"] as Array[StringName]
	map.add_room(entry)
	var rest := _room(
		&"rest", &"settlement", [&"entry", &"vault"] as Array[StringName], [&"treasure_keyed"]
	)
	rest.size = Vector2i(12, 10)
	map.add_room(rest)
	var vault := _room(&"vault", &"chamber", [&"rest", &"gauntlet", &"core"] as Array[StringName])
	vault.size = Vector2i(14, 12)
	vault.actor_spawn_refs = [_spawn("v1", "mob", 2)] as Array[Dictionary]
	map.add_room(vault)
	var gauntlet := _room(&"gauntlet", &"arena", [&"vault"] as Array[StringName], [&"elite_guard"])
	gauntlet.size = Vector2i(16, 16)
	gauntlet.actor_spawn_refs = [_spawn("g1", "miniboss")] as Array[Dictionary]
	map.add_room(gauntlet)
	var core := _room(&"core", &"core", [&"vault"] as Array[StringName], [&"boss_worthy"])
	core.actor_spawn_refs = [_spawn("b1", "boss")] as Array[Dictionary]
	map.add_room(core)
	map.entry_room = &"entry"
	map.weather = &"dry_wind"
	return map


## A map whose rooms hold one of every POI tag, so the tag -> marker table is proven
## end to end rather than one row at a time.
func _every_tag_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(60, 20), 5)
	var tags: Array[StringName] = [&"refuge", &"treasure_keyed", &"puzzle_formation"]
	for index in range(tags.size()):
		var room_id := StringName("poi_%d" % index)
		var room := _room(room_id, &"chamber", [] as Array[StringName], [tags[index]])
		room.roster_band = &"empty"
		map.add_room(room)
	for index in range(2):
		var guard_id := StringName("guard_%d" % index)
		var guard := _room(
			guard_id,
			&"chamber",
			[] as Array[StringName],
			[&"elite_guard", &"boss_worthy"] as Array[StringName]
		)
		guard.roster_band = &"empty"
		map.add_room(guard)
	map.entry_room = &"poi_0"
	return map


func _actor() -> Actor:
	return Actor.new(&"minimap_tester", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})


## An actor inside `map`, discovering `room_ids` through the facade. The minimap's fog
## reads `DomainApi.discovered`, so the fixture must SET it the same way play does.
func _actor_in(map: DomainMap, room_ids: Array[StringName] = [] as Array[StringName]) -> Actor:
	var actor := _actor()
	DomainApi.enter(actor, map, &"ember_hollow")
	for room_id in room_ids:
		DomainApi.visit_room(actor, room_id)
	return actor


# ── fog ──────────────────────────────────────────────────────────────────────


## Fog is DISCOVERY. `vault` is one hop from the discovered `rest` and therefore
## trivially reachable, and it is still not drawn: reachability is not knowledge.
func test_only_discovered_rooms_are_drawn() -> void:
	var map := _tiered_map()
	var actor := _actor_in(map, [&"rest"] as Array[StringName])
	var rooms: Array = DomainMinimap.render(actor, map)["rooms"]
	var drawn: Array = []
	for row in rooms:
		drawn.append(row["room_id"])
	assert_eq(drawn.has("entry"), true, "the entry is always known")
	assert_eq(drawn.has("rest"), true, "a visited room is drawn")
	assert_eq(drawn.has("vault"), false, "an unvisited but reachable room is NOT drawn")
	assert_eq(drawn.has("gauntlet"), false, "nor is anything behind it")
	assert_eq(drawn.has("core"), false, "nor the boss room: tier legibility is not a spoiler")


## The frontier is the shape of the map, not the state of the player: an undiscovered
## room's tags must not leak through the POI layer.
func test_fog_covers_every_layer() -> void:
	var map := _tiered_map()
	var payload := DomainMinimap.render(_actor_in(map, [&"vault"] as Array[StringName]), map)
	assert_eq(payload["pois"].size(), 0, "nothing is marked before it is found")
	assert_eq(payload["discovered"], ["entry", "vault"] as Array, "discovered is canonical")


func test_render_refuses_without_an_actor_or_a_map() -> void:
	assert_eq(DomainMinimap.render(null, _tiered_map()), {}, "no actor, no minimap")
	assert_eq(DomainMinimap.render(_actor(), null), {}, "no map, no minimap")
	assert_eq(DomainMinimap.summary(), {}, "the summary of no domain is {}")


# ── the room layer ───────────────────────────────────────────────────────────


func test_room_flags_are_correct() -> void:
	var map := _tiered_map()
	var payload := DomainMinimap.render(_actor_in(map, [&"core"] as Array[StringName]), map)
	var by_id := {}
	for row in payload["rooms"]:
		by_id[row["room_id"]] = row
	assert_eq(by_id.size(), map.room_count(), "the whole domain is drawn once discovered")
	assert_eq(by_id["entry"]["is_entry"], true, "the entry is flagged")
	assert_eq(by_id["rest"]["is_entry"], false, "and no other room claims it")
	assert_eq(by_id["core"]["is_core"], true, "a `core` kind is the core room")
	assert_eq(by_id["vault"]["is_core"], false, "a chamber is not the core")
	assert_eq(by_id["entry"]["hostile"], false, "an `empty` breather is not hostile")
	assert_eq(by_id["rest"]["hostile"], false, "a settlement holds npcs, not hostiles")
	assert_eq(by_id["vault"]["hostile"], true, "a chamber permits a fight")
	assert_eq(by_id["vault"]["reachable"], true, "reachability is reported alongside fog")
	for row in payload["rooms"]:
		assert_eq(row["discovered"], true, "every drawn room is discovered")
		assert_eq(row["rect"].size(), 4, "a rect is [x, y, w, h]")


## TIER LEGIBILITY (ADR 0073): an `arena` promises a miniboss and a `core` a boss
## BEFORE anything is fought. Both promises here are authored — a miniboss role, a boss
## role — so the test cannot pass on a shape heuristic alone.
func test_an_arena_promises_a_miniboss_and_a_core_a_boss() -> void:
	var map := _tiered_map()
	var payload := DomainMinimap.render(_actor_in(map, [&"core"] as Array[StringName]), map)
	var tiers := {}
	for row in payload["rooms"]:
		tiers[row["room_id"]] = row["tier"]
	assert_eq(tiers["gauntlet"], "miniboss", "an arena is a miniboss")
	assert_eq(tiers["core"], "boss", "a core is a boss")
	assert_eq(tiers["vault"], "room", "an ordinary chamber promises nothing")
	assert_eq(tiers["rest"], "room", "a settlement is not a fight")
	assert_eq(tiers["entry"], "room", "and the breather is not one either")


## The shape alone is enough when nothing else is authored, because `kind` is a closed
## vocabulary and not a heuristic — this is the fallback, not the primary source.
func test_tier_falls_back_to_the_room_kind() -> void:
	var map := DomainMap.new(Vector2i(20, 20), 1)
	var entry := _room(&"entry", &"floor", [&"pit"] as Array[StringName])
	entry.roster_band = &"empty"
	map.add_room(entry)
	var pit := _room(&"pit", &"arena", [&"entry"] as Array[StringName])
	map.add_room(pit)
	map.entry_room = &"entry"
	var payload := DomainMinimap.render(_actor_in(map), map)
	assert_eq(payload["rooms"][1]["room_id"], "pit", "canonical order puts the pit second")
	assert_eq(
		payload["rooms"][1]["tier"], "miniboss", "an authored-empty arena still promises a miniboss"
	)


## Depth is not a tier. A room that happens to be reached last is not a boss room, and
## the post-hoc heuristic ADR 0073 forbids is exactly that.
func test_depth_alone_never_promotes_a_room() -> void:
	var map := _tiered_map()
	var payload := DomainMinimap.render(_actor_in(map, [&"core"] as Array[StringName]), map)
	for row in payload["rooms"]:
		if row["room_id"] != "core":
			assert_eq(row["tier"], "room", "'%s' is as deep and not a tier" % row["room_id"])


# ── POIs ─────────────────────────────────────────────────────────────────────


## ADR 0073 names room tags as the ONE source for the minimap POI layer, so the test
## walks the marker back to the tag rather than checking a marker exists.
func test_every_marker_traces_back_to_a_tag_on_its_room() -> void:
	var map := _every_tag_map()
	var actor := _actor_in(map)
	for tag in DomainMinimap.POI_TAGS:
		DomainApi.visit_room(actor, StringName("poi_0"))
	var payload := DomainMinimap.render(actor, map)
	assert_eq(payload["pois"].size() > 0, true, "the fixture has markers to check")
	for poi in payload["pois"]:
		var room := map.room(StringName(poi["room_id"]))
		assert_ne(room, null, "a marker names a real room")
		assert_eq(
			room.has_tag(StringName(poi["tag"])), true, "the tag '%s' is on the room" % poi["tag"]
		)
		assert_eq(
			DomainMinimap.POI_BY_TAG.get(StringName(poi["tag"]), ""),
			poi["marker"],
			"and the marker is the one that tag maps to"
		)


## Each of the five tags maps to a DISTINCT marker kind, so two rooms that promise
## different things cannot be drawn the same.
func test_the_five_poi_tags_map_to_distinct_markers() -> void:
	var map := _every_tag_map()
	var actor := _actor_in(map)
	for room_id in map.room_ids_sorted():
		DomainApi.visit_room(actor, room_id)
	var markers := {}
	for poi in DomainMinimap.render(actor, map)["pois"]:
		markers[poi["marker"]] = true
	assert_eq(
		markers.size(), DomainMinimap.POI_TAGS.size(), "five tags, five markers: %s" % str(markers)
	)
	for tag in DomainMinimap.POI_TAGS:
		assert_eq(DomainMinimap.POI_BY_TAG.has(tag), true, "'%s' is a published POI tag" % tag)


func test_a_tag_the_minimap_does_not_know_marks_nothing() -> void:
	var map := _tiered_map()
	map.room(&"vault").tags = [&"not_a_known_tag"] as Array[StringName]
	var payload := DomainMinimap.render(_actor_in(map, [&"vault"] as Array[StringName]), map)
	assert_eq(payload["pois"].size(), 0, "an unknown tag is content, not a marker to invent")


# ── zones and weather ────────────────────────────────────────────────────────


## ADR 0075: the minimap reports what a room will do to you and the levers that
## answer it, so a player can route around a hazard instead of discovering it.
func test_severe_environments_are_flattened_with_their_room_and_levers() -> void:
	var map := _tiered_map()
	map.room(&"vault").environment_zones = (
		[_zone(&"furnace", &"super_hot", EnvironmentZoneDef.BAND_SEVERE)]
		as Array[EnvironmentZoneDef]
	)
	var zones: Array = DomainMinimap.render(_actor_in(map, [&"vault"]), map)["zones"]
	assert_eq(zones.size(), 1, "one zone")
	assert_eq(zones[0]["room_id"], "vault", "flattened with its room")
	assert_eq(zones[0]["kind"], "super_hot", "and its kind")
	assert_eq(zones[0]["severity"], "med", "the authored band reads as a severity word")
	assert_eq(zones[0]["mitigation_tags"], ["gear", "affinity"] as Array, "and its levers")


func test_a_zone_is_visible_before_the_room_is_found() -> void:
	# Deliberate and asserted rather than incidental: a hazard you cannot see is a
	# hazard you meet rather than avoid.
	var map := _tiered_map()
	map.room(&"vault").environment_zones = (
		[_zone(&"furnace", &"super_hot", 3)] as Array[EnvironmentZoneDef]
	)
	var zones: Array = DomainMinimap.render(_actor_in(map), map)["zones"]
	assert_eq(zones.size(), 1, "the zone is reported with only the entry discovered")
	assert_eq(zones[0]["severity"], "high", "and its band is read")


func test_weather_is_surfaced_in_the_read_model() -> void:
	var map := _tiered_map()
	assert_eq(map.weather, &"dry_wind", "the map carries the bias")
	var payload := DomainMinimap.render(_actor_in(map), map)
	assert_eq(payload["weather"], "dry_wind", "and the minimap reports it")
	# `visit_room` records the bias through the facade; the minimap must show the
	# RECORDED one, not a stale map object.
	var actor := _actor_in(map)
	DomainApi.visit_room(actor, &"vault", &"ashfall")
	assert_eq(
		DomainMinimap.render(actor, DomainMap.from_dict(map.to_dict()))["weather"],
		"dry_wind",
		"a map the minimap is handed is the map it reports, never a guess"
	)


# ── primitives ───────────────────────────────────────────────────────────────


func test_the_payload_is_json_clean_primitives() -> void:
	var map := _tiered_map()
	map.room(&"vault").environment_zones = (
		[_zone(&"furnace", &"toxic", 2)] as Array[EnvironmentZoneDef]
	)
	var payload := DomainMinimap.render(_actor_in(map, [&"core"] as Array[StringName]), map)
	var parsed: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_eq(
		parsed is Dictionary and not (parsed as Dictionary).is_empty(),
		true,
		"the minimap is primitives only: no Vector2, no Rect2i, no StringName"
	)
	# And the round trip is lossless, which is what makes the headless driver and a
	# screen read the same thing.
	assert_eq(JSON.stringify(parsed), JSON.stringify(payload), "a JSON round trip loses nothing")


func test_render_is_deterministic() -> void:
	var map := _tiered_map()
	var first := JSON.stringify(DomainMinimap.render(_actor_in(map, [&"vault"]), map))
	var second := JSON.stringify(DomainMinimap.render(_actor_in(map, [&"vault"]), map))
	assert_eq(first, second, "the same domain and the same discovery render identically")


func test_layout_and_bounds_describe_the_drawn_rooms() -> void:
	var map := _tiered_map()
	var payload := DomainMinimap.render(_actor_in(map), map)
	assert_eq(payload["layout"].size(), map.room_count(), "a rect for every room in the domain")
	assert_eq(payload["bounds"].size(), 4, "bounds are [x, y, w, h]")
	var box: Array = payload["bounds"]
	assert_eq(
		int(box[2]) > 0 and int(box[3]) > 0, true, "and they are non-degenerate: %s" % str(box)
	)
	for row in payload["rooms"]:
		var rect: Array = row["rect"]
		assert_eq(payload["layout"].has(row["room_id"]), true, "each room's rect is in the layout")
		assert_eq(rect.size(), 4, "as [x, y, w, h]")


func test_routes_reach_the_minimap_without_a_reachable_pair() -> void:
	var map := _tiered_map()
	var routes: Array = DomainMinimap.render(_actor_in(map, [&"core"]), map)["routes"]
	assert_eq(routes.size(), DomainPaths.routes(map).size(), "the minimap carries the corridor set")
	assert_eq(routes.size() > 0, true, "a five-room domain has corridors")
	for route in routes:
		assert_eq(route["points"].size() >= 2, true, "each one is a polyline")
		for point in route["points"]:
			assert_eq(point.size(), 2, "of [x, y] pairs")
