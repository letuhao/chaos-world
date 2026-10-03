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


# ── the authored content catalogue and the one production entry point ─────────


func test_templates_lists_the_authored_domains() -> void:
	var templates := DomainApi.templates()
	assert_eq(templates.is_empty(), false, "the authored catalogue is reachable from the facade")
	var ids: Array[String] = []
	for entry in templates:
		ids.append(entry["template_id"])
	assert_eq(ids.size(), templates.size(), "every catalogue row names its template")
	for entry in templates:
		assert_eq(entry["template_id"] != "", true, "no anonymous template")
		assert_eq(entry["rooms_in_pool"] > 0, true, "a template with no room pool is not a domain")
		assert_eq(entry["min_rooms"] > 0, true, "a template declares a room floor")
		assert_eq(entry["path"].ends_with(".tres"), true, "and the path it was loaded from")


func test_templates_are_canonically_ordered() -> void:
	var first := DomainApi.templates()
	var second := DomainApi.templates()
	assert_eq(first.size(), second.size(), "the catalogue is stable between calls")
	var names: Array[String] = []
	for entry in first:
		names.append(entry["template_id"])
	assert_eq(names, _sorted(names), "template ids are in canonical order, not directory order")


func test_generate_and_enter_produces_a_playable_run() -> void:
	var actor := _actor()
	var templates := DomainApi.templates()
	assert_eq(templates.is_empty(), false, "there is something to generate")
	var result := DomainApi.generate_and_enter(actor, StringName(templates[0]["template_id"]), 7)
	assert_eq(result.get("ok"), true, "generate_and_enter succeeds: %s" % str(result))
	# The whole chain is exercised: template -> DomainMap -> contract -> active run.
	assert_eq(DomainApi.map_summary(actor).get("room_count") > 0, true, "a real map is active")
	assert_eq(DomainApi.rooms(actor).size() > 0, true, "with rooms")
	assert_eq(DomainApi.population(actor).size() > 0, true, "and a population to walk into")


func test_generate_and_enter_refuses_by_name() -> void:
	var actor := _actor()
	var missing := DomainApi.generate_and_enter(actor, &"no_such_domain", 1)
	assert_eq(missing.get("ok"), false, "an unknown template is refused")
	assert_eq(missing.get("reason"), DomainApi.ERR_NO_TEMPLATE, "with a named reason")
	assert_eq(DomainApi.map_summary(actor), {}, "and no run was started")
	assert_eq(
		DomainApi.generate_and_enter(null, &"ember_grotto", 1).get("reason"),
		DomainApi.ERR_NO_ACTOR,
		"a null actor is refused"
	)


func test_the_same_seed_gives_the_same_run_twice() -> void:
	var templates := DomainApi.templates()
	if templates.is_empty():
		assert_eq(true, true, "no templates authored; nothing to compare")
		return
	var template_id := StringName(templates[0]["template_id"])
	var first := _actor()
	var second := _actor()
	DomainApi.generate_and_enter(first, template_id, 1234)
	DomainApi.generate_and_enter(second, template_id, 1234)
	assert_eq(
		JSON.stringify(DomainApi.summary(first)),
		JSON.stringify(DomainApi.summary(second)),
		"the same template and seed produce the identical run (AC6 through the facade)"
	)


func test_summary_carries_the_whole_map_for_the_driver() -> void:
	var actor := _actor()
	DomainApi.generate_and_enter(actor, StringName(DomainApi.templates()[0]["template_id"]), 3)
	var summary := DomainApi.summary(actor)
	# The driver renders the domain from this ONE dictionary, so the full map has to be
	# here - not only the counts.
	assert_eq(summary.has("map_data"), true, "summary carries the full map")
	var rooms_in_map: int = (summary["map_data"] as Dictionary)["rooms"].size()
	assert_eq(rooms_in_map, summary["rooms"], "the carried map agrees with the room count")
	assert_eq(summary["discovered"], 1, "a fresh run has discovered only its entry")


func _sorted(values: Array[String]) -> Array[String]:
	var out := values.duplicate()
	out.sort()
	return out


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
