extends TestCase

## ADR 0072: the DomainApi facade — enter/leave a domain, discover rooms, and report.
##
## The facade is the ONLY surface another module or a screen may touch, and it is
## capped at 12 public methods (tools/arch/rules.py:104). This suite also proves the
## cap holds, because a facade that quietly grows past it fails the gate for everyone.

# ── fixtures ─────────────────────────────────────────────────────────────────


func _spawn(ref_id: String, inhabitant_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": inhabitant_id, "role": role, "count": count}


func _room(room_id: StringName, kind: StringName, exits: Array[StringName]) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	return room


func _map() -> DomainMap:
	var map := DomainMap.new(Vector2i(32, 24), 4242)
	# The entry is an authored `empty` breather: a `floor` defaults to the hostile
	# `skirmish` band, and a run that opens with a fight is not a run you can walk out of.
	var entry := _room(&"entry", &"floor", [&"hall"] as Array[StringName])
	entry.roster_band = &"empty"
	map.add_room(entry)
	var hall := _room(&"hall", &"chamber", [&"entry", &"core"] as Array[StringName])
	hall.actor_spawn_refs = [_spawn("g1", "cinder_hound", "mob", 2)] as Array[Dictionary]
	map.add_room(hall)
	var core := _room(&"core", &"core", [&"hall"] as Array[StringName])
	core.actor_spawn_refs = [_spawn("b1", "ash_warden", "boss", 1)] as Array[Dictionary]
	map.add_room(core)
	map.entry_room = &"entry"
	return map


func _actor() -> Actor:
	return Actor.new(&"domain_tester", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})


# ── the cap ──────────────────────────────────────────────────────────────────


## The facade is at the cap by design (world and loot are both full), so this asserts
## the count rather than trusting that nobody added a thirteenth verb.
##
## Counted from the SCRIPT TEXT, not from reflection: `tools arch` counts `static func`
## declarations the same way, so this is the same number the gate enforces. Reflection
## is unavailable here — `get_method_list()` is an instance method and every facade verb
## is static.
func test_facade_stays_within_the_cap() -> void:
	var script := load("res://src/modules/domain/api.gd") as GDScript
	var source: String = script.source_code
	var count := 0
	for line in source.split("\n"):
		if line.begins_with("static func ") and not line.contains("static func _"):
			count += 1
	assert_eq(count <= 12, true, "DomainApi declares %d public static methods (cap 12)" % count)
	assert_eq(count > 0, true, "and the count is real, not an artefact of the parse")


# ── enter / leave ────────────────────────────────────────────────────────────


func test_enter_then_leave_round_trips() -> void:
	var actor := _actor()
	var result := DomainApi.enter(actor, _map(), &"ember_hollow")
	assert_eq(result.get("ok"), true, "enter succeeds: %s" % str(result))
	assert_eq(result.get("room_count"), 3, "three rooms")
	assert_eq(DomainApi.map_summary(actor).get("domain_id"), "ember_hollow", "the run is recorded")

	var left := DomainApi.leave(actor)
	assert_eq(left.get("ok"), true, "leave succeeds")
	assert_eq(DomainApi.map_summary(actor), {}, "no map outside a run")


func test_enter_refuses_a_map_that_fails_the_contract() -> void:
	var actor := _actor()
	var broken := _map()
	# A dangling exit is exactly the defect that would strand a player mid-run.
	broken.room(&"hall").exits.append(&"nowhere")
	var result := DomainApi.enter(actor, broken, &"broken")
	assert_eq(result.get("ok"), false, "a broken map is refused")
	assert_eq(result.get("reason"), DomainApi.ERR_INVALID_CONTRACT, "with a named reason")
	assert_eq((result.get("problems") as Array).size() > 0, true, "naming what is wrong")


func test_enter_refuses_a_null_actor_and_null_map() -> void:
	assert_eq(DomainApi.enter(null, _map()).get("reason"), DomainApi.ERR_NO_ACTOR, "no actor")
	assert_eq(DomainApi.enter(_actor(), null).get("reason"), DomainApi.ERR_NO_MAP, "no map")


func test_leave_outside_a_run_is_refused() -> void:
	assert_eq(DomainApi.leave(_actor()).get("reason"), DomainApi.ERR_NO_MAP, "nothing to leave")


# ── discovery ────────────────────────────────────────────────────────────────


func test_visit_records_discovery_in_canonical_order() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	DomainApi.visit_room(actor, &"core")
	DomainApi.visit_room(actor, &"hall")
	var discovered := DomainApi.discovered(actor) as Array
	assert_eq(discovered, ["core", "entry", "hall"], "sorted, and the entry was pre-seeded")


func test_revisiting_is_idempotent() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var first := DomainApi.visit_room(actor, &"hall")
	var second := DomainApi.visit_room(actor, &"hall")
	assert_eq(first.get("newly_discovered"), true, "the first visit discovers")
	assert_eq(second.get("newly_discovered"), false, "the second does not")
	assert_eq((DomainApi.discovered(actor) as Array).size(), 2, "entry plus hall, no duplicate")


func test_visit_unknown_room_is_refused() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var result := DomainApi.visit_room(actor, &"elsewhere")
	assert_eq(result.get("ok"), false, "an unknown room is refused")
	assert_eq(result.get("reason"), DomainApi.ERR_UNKNOWN_ROOM, "with a named reason")


func test_discovery_survives_leaving() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	DomainApi.visit_room(actor, &"core")
	DomainApi.leave(actor)
	# entry was seeded on enter and core was visited: two rooms, and leaving keeps both.
	assert_eq(
		DomainApi.discovered(actor) as Array,
		["core", "entry"],
		"the map remembers you; the run does not"
	)


func test_visit_outside_a_run_is_refused() -> void:
	assert_eq(
		DomainApi.visit_room(_actor(), &"entry").get("reason"),
		DomainApi.ERR_NO_MAP,
		"no active map"
	)


# ── the read model ───────────────────────────────────────────────────────────


func test_summary_is_empty_outside_a_run() -> void:
	assert_eq(DomainApi.summary(_actor()), {}, "no run, no report")
	assert_eq(DomainApi.rooms(_actor()).size(), 0, "no run, no rooms")
	assert_eq(DomainApi.population(_actor()).size(), 0, "no run, no population")
	assert_eq(DomainApi.environment_zones(_actor()).size(), 0, "no run, no zones")


func test_map_summary_reports_shape_and_counts() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var summary := DomainApi.map_summary(actor)
	assert_eq(summary.get("room_count"), 3, "three rooms")
	assert_eq(summary.get("reachable"), 3, "all reachable")
	assert_eq(summary.get("seed"), 4242, "the seed is reported")
	assert_eq(summary.get("hostile_rooms"), 2, "hall and core are hostile; the entry is a breather")
	assert_eq(summary.get("entry_kind"), "floor", "the entry room's kind")
	assert_eq(summary.get("spawn_count"), 2, "two authored spawn refs")


func test_summary_is_primitives_only() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	# The UI contract is primitives only, so an agent and a screen read it identically.
	var parsed: Variant = JSON.parse_string(JSON.stringify(DomainApi.summary(actor)))
	assert_eq(parsed is Dictionary, true, "summary is JSON-clean")


func test_rooms_are_canonical_and_carry_reachability() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var rooms := DomainApi.rooms(actor)
	assert_eq(rooms.size(), 3, "three rooms")
	assert_eq(rooms[0]["room_id"], "core", "canonical order: core, entry, hall")
	for entry in rooms:
		assert_eq(entry.has("reachable"), true, "every room reports reachability")


func test_room_lookup_refuses_an_unknown_room() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	assert_eq(DomainApi.room(actor, &"hall").get("room_id"), "hall", "a known room resolves")
	assert_eq(DomainApi.room(actor, &"nowhere"), {}, "an unknown room yields {}, never a guess")


func test_population_reports_roles_not_classes() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var population := DomainApi.population(actor)
	assert_eq(population.size(), 2, "two refs")
	# Canonical order is by room_id, so `core` sorts before `hall`.
	assert_eq(population[0]["room_id"], "core", "canonical room order")
	assert_eq(population[0]["role"], "boss", "the core's boss")
	assert_eq(population[1]["room_id"], "hall", "then the hall")
	assert_eq(population[1]["role"], "mob", "the hall's mob group")
	assert_eq(population[1]["count"], 2, "a group is a count, not two rows")


# ── state hygiene ────────────────────────────────────────────────────────────


func test_state_is_string_keyed_in_module_data() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	# ADR 0027: module_data is String-keyed and JSON-round-tripped; a Vector2 in here
	# would silently break every save.
	var parsed: Variant = JSON.parse_string(
		JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY))
	)
	assert_eq(parsed is Dictionary, true, "domain state is JSON-clean")


func test_state_survives_an_actor_round_trip() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	DomainApi.visit_room(actor, &"core")
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(DomainApi.map_summary(restored).get("room_count"), 3, "the run survives save/load")
	assert_eq(DomainApi.discovered(restored) as Array, ["core", "entry"], "discovery survives too")


# ── weather ──────────────────────────────────────────────────────────────────


func test_weather_is_recorded_and_never_a_zone_of_its_own() -> void:
	var actor := _actor()
	DomainApi.enter(actor, _map(), &"ember_hollow")
	var before := DomainApi.environment_zones(actor).size()
	DomainApi.visit_room(actor, &"hall", &"dry_wind")
	assert_eq(DomainApi.map_summary(actor).get("weather"), "dry_wind", "weather is recorded")
	assert_eq(
		DomainApi.environment_zones(actor).size(),
		before,
		"weather re-weights authored zones and never invents one"
	)
