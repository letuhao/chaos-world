extends TestCase

## ADR 0072/0073: the DomainMap contract, held by BOTH producers.
##
## AC1 — a handcrafted map and a seeded generated map pass the SAME contract test.
## AC6 — the same seed produces a byte-identical map; a different seed does not.
##
## These are unit tests with no scene tree: `DomainMap` is engine-agnostic on purpose.

# ── fixtures ─────────────────────────────────────────────────────────────────


func _zone(zone_id: StringName, kind: StringName, intensity: int = 2) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = zone_id
	zone.kind = kind
	zone.intensity = intensity
	zone.status_id = &"env_scourge"
	zone.mitigation_tags = [&"gear", &"affinity"] as Array[StringName]
	zone.bounds = Rect2i(0, 0, 4, 4)
	return zone


func _spawn(ref_id: String, inhabitant_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": inhabitant_id, "role": role, "count": count}


func _room(room_id: StringName, kind: StringName, exits: Array[StringName]) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	return room


## A handcrafted domain: three rooms in a line, an authored core. This is the shape a
## scene's markers produce once they are READ INTO a map (never played directly).
func handcrafted_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(32, 24), 0)
	map.add_room(_room(&"entry_grove", &"floor", [&"ember_flue"] as Array[StringName]))
	map.add_room(
		_room(&"ember_flue", &"corridor", [&"entry_grove", &"heart_of_ashes"] as Array[StringName])
	)
	var core := _room(&"heart_of_ashes", &"core", [&"ember_flue"] as Array[StringName])
	core.actor_spawn_refs = [_spawn("b1", "ash_warden", "boss", 1)] as Array[Dictionary]
	map.add_room(core)
	map.entry_room = &"entry_grove"
	return map


## A generated domain assembled from the same authored room kit, at a given seed. The
## generator proper lands with the template loader; this stands in for its output so the
## PARITY claim is testable before it exists.
func generated_map(seed_value: int) -> DomainMap:
	var map := DomainMap.new(Vector2i(48, 32), seed_value)
	var entry := _room(&"entry", &"floor", [&"hall"] as Array[StringName])
	map.add_room(entry)
	var hall := _room(&"hall", &"chamber", [&"entry", &"vault"] as Array[StringName])
	hall.actor_spawn_refs = [_spawn("g1", "cinder_hound", "mob", 2)] as Array[Dictionary]
	map.add_room(hall)
	var vault := _room(&"vault", &"core", [&"hall"] as Array[StringName])
	vault.actor_spawn_refs = [_spawn("b1", "ash_warden", "boss", 1)] as Array[Dictionary]
	map.add_room(vault)
	map.entry_room = &"entry"
	return map


# ── AC1: both producers pass ONE contract ────────────────────────────────────


func test_handcrafted_map_satisfies_contract() -> void:
	var problems := DomainMapContract.assert_valid(handcrafted_map())
	assert_eq(problems.size(), 0, "handcrafted map problems: %s" % ", ".join(problems))


func test_generated_map_satisfies_contract() -> void:
	for seed_value in [1, 7, 42, 99, 104729]:
		var map := generated_map(seed_value)
		var problems := DomainMapContract.assert_valid(map)
		assert_eq(
			problems.size(), 0, "generated seed %d problems: %s" % [seed_value, ", ".join(problems)]
		)


## The parity claim itself: the contract is a function of the map's properties, not of
## which producer made it. Both maps clear the SAME assertion set.
func test_both_producers_pass_the_same_assertions() -> void:
	var handcrafted := handcrafted_map()
	var generated := generated_map(7)
	assert_eq(
		DomainMapContract.assert_valid(handcrafted).size(),
		DomainMapContract.assert_valid(generated).size(),
		"both producers are checked against the identical assertion set"
	)
	# And the map shape the two share: both carry rooms of several kinds, drawn from the
	# one closed vocabulary — there is no separate kit for a generated map.
	assert_eq(handcrafted.kinds_present().size() > 1, true, "handcrafted rooms use several kinds")
	assert_eq(generated.kinds_present().size() > 1, true, "generated rooms use several kinds")
	for kind in generated.kinds_present():
		assert_eq(RoomDef.KINDS.has(kind), true, "generated kind '%s' is in the closed set" % kind)


# ── AC6: determinism ─────────────────────────────────────────────────────────


func test_same_seed_is_byte_identical() -> void:
	var first := JSON.stringify(generated_map(1234).to_dict())
	var second := JSON.stringify(generated_map(1234).to_dict())
	assert_eq(first, second, "same seed produces a byte-identical map")


func test_different_seed_differs() -> void:
	var a := JSON.stringify(generated_map(1).to_dict())
	var b := JSON.stringify(generated_map(2).to_dict())
	assert_eq(a != b, true, "a different seed produces a different map")


func test_to_dict_from_dict_round_trips() -> void:
	var original := handcrafted_map()
	var restored := DomainMap.from_dict(original.to_dict())
	assert_eq(
		JSON.stringify(restored.to_dict()),
		JSON.stringify(original.to_dict()),
		"DomainMap survives a JSON round trip"
	)


func test_map_is_json_clean() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(handcrafted_map().to_dict()))
	assert_eq(
		parsed is Dictionary and not (parsed as Dictionary).is_empty(),
		true,
		"a DomainMap is JSON-clean: no Vector2, no Node, no Resource"
	)


# ── connectivity: the loud-fail rules ─────────────────────────────────────────


func test_unreachable_room_is_reported() -> void:
	var map := handcrafted_map()
	# An orphan the entry cannot walk to.
	map.add_room(_room(&"lost_hall", &"chamber", [] as Array[StringName]))
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(
		_contains(problems, "unreachable"),
		true,
		"an orphan room is reported: %s" % ", ".join(problems)
	)


func test_dangling_exit_is_reported() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").exits.append(&"nowhere")
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "does not resolve"), true, "a dangling exit is reported")


func test_map_with_no_exit_is_reported() -> void:
	var map := DomainMap.new()
	map.add_room(_room(&"only", &"floor", [] as Array[StringName]))
	map.entry_room = &"only"
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "no exit"), true, "a map with no exit is reported")


func test_unknown_room_kind_is_reported() -> void:
	var map := handcrafted_map()
	map.room(&"entry_grove").kind = &"not_a_kind"
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "unknown kind"), true, "an unknown room kind is reported")


func test_spawn_ref_in_an_empty_room_is_reported() -> void:
	var map := handcrafted_map()
	var grove := map.room(&"entry_grove")
	grove.kind = &"settlement"
	grove.actor_spawn_refs = [_spawn("n1", "elder", "npc", 1)] as Array[Dictionary]
	# A `social` band legitimately holds an npc, so this alone is CORRECT content. Flipping
	# it to `empty` makes it wrong: an `empty` room is a breather and takes no spawn at all.
	grove.roster_band = &"empty"
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(
		_contains(problems, "does not permit"),
		true,
		"a spawn ref in an `empty` breather room is reported: %s" % ", ".join(problems)
	)


func test_a_social_room_may_hold_an_npc() -> void:
	# The counterpart to the test above: `social` exists to hold inhabitants, so an npc
	# elder in a settlement is legal and must NOT be reported. Without this, the rule
	# would be satisfied by simply forbidding every spawn in every non-hostile room.
	var map := handcrafted_map()
	var grove := map.room(&"entry_grove")
	grove.kind = &"settlement"
	grove.roster_band = &"social"
	grove.actor_spawn_refs = [_spawn("n1", "elder", "npc", 1)] as Array[Dictionary]
	assert_eq(
		DomainMapContract.assert_valid(map).size(),
		0,
		(
			"a settlement holding an npc passes the contract: %s"
			% ", ".join(DomainMapContract.assert_valid(map))
		)
	)


func test_a_social_room_refuses_a_hostile_role() -> void:
	# A settlement is not a battlefield: a mob in a `social` band is as wrong as any
	# spawn in an `empty` one, and the rule must catch both.
	var map := handcrafted_map()
	var grove := map.room(&"entry_grove")
	grove.kind = &"settlement"
	grove.roster_band = &"social"
	grove.actor_spawn_refs = [_spawn("m1", "hound", "mob", 1)] as Array[Dictionary]
	assert_eq(
		_contains(DomainMapContract.assert_valid(map), "does not permit"),
		true,
		"a mob in a social room is reported"
	)


func test_unknown_role_is_reported() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").kind = &"floor"
	map.room(&"ember_flue").actor_spawn_refs = (
		[_spawn("x", "who", "dragon", 1)] as Array[Dictionary]
	)
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "unknown role"), true, "an unknown role is reported")


# ── ADR 0075: environment zones ─────────────────────────────────────────────


func test_zone_without_mitigation_is_reported() -> void:
	var map := handcrafted_map()
	var zone := _zone(&"furnace", &"super_hot")
	zone.mitigation_tags = [] as Array[StringName]
	map.room(&"ember_flue").environment_zones = [zone] as Array[EnvironmentZoneDef]
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(
		_contains(problems, "no mitigation_tags"),
		true,
		"a flat damage tax is reported: %s" % ", ".join(problems)
	)


func test_zone_with_unknown_lever_is_reported() -> void:
	var map := handcrafted_map()
	var zone := _zone(&"furnace", &"super_hot")
	zone.mitigation_tags = [&"charm"] as Array[StringName]
	map.room(&"ember_flue").environment_zones = [zone] as Array[EnvironmentZoneDef]
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "names no lever"), true, "an unknown lever is reported")


func test_affinity_only_zone_is_reported() -> void:
	var map := handcrafted_map()
	var zone := _zone(&"furnace", &"super_hot")
	zone.mitigation_tags = [&"affinity"] as Array[StringName]
	map.room(&"ember_flue").environment_zones = [zone] as Array[EnvironmentZoneDef]
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(
		_contains(problems, "wrong"),
		true,
		"an affinity-only zone denies the wrong root a counterplay"
	)


func test_unknown_zone_kind_is_reported() -> void:
	var map := handcrafted_map()
	var zone := _zone(&"furnace", &"lava")
	map.room(&"ember_flue").environment_zones = [zone] as Array[EnvironmentZoneDef]
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(_contains(problems, "unknown kind"), true, "an unknown zone kind is reported")


## BL-0063: the newest kind is covered by the SAME contract, not a parallel path — the
## kind set the contract reads is the zone def's own catalogue, so a kind added there is
## covered here by construction, and this test is what proves it.
func test_a_ley_line_zone_satisfies_the_contract() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").environment_zones = (
		[_zone(&"ley_vein", &"ley_line")] as Array[EnvironmentZoneDef]
	)
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(problems.is_empty(), true, "the ley line is a legal zone: %s" % ", ".join(problems))


func test_valid_zone_passes() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").environment_zones = (
		[_zone(&"furnace", &"super_hot", 3)] as Array[EnvironmentZoneDef]
	)
	var problems := DomainMapContract.assert_valid(map)
	assert_eq(problems.size(), 0, "a well-authored zone passes: %s" % ", ".join(problems))


func test_zone_magnitude_is_authored_per_band() -> void:
	var scorch := _zone(&"f", &"super_hot", EnvironmentZoneDef.BAND_SCORCH)
	var severe := _zone(&"f", &"super_hot", EnvironmentZoneDef.BAND_SEVERE)
	var annihilating := _zone(&"f", &"super_hot", EnvironmentZoneDef.BAND_ANNIHILATING)
	assert_eq(scorch.magnitude() < severe.magnitude(), true, "band 1 < band 2")
	assert_eq(severe.magnitude() < annihilating.magnitude(), true, "band 2 < band 3")
	assert_eq(scorch.magnitude(), 0.35, "authored magnitude, not a computed curve")


func test_unknown_zone_kind_has_no_magnitude() -> void:
	var zone := _zone(&"f", &"lava")
	assert_eq(zone.magnitude(), 0.0, "an unknown kind mitigates nothing and hits for nothing")


# ── ADR 0074: roles are tags, never classes ──────────────────────────────────


func test_roles_are_closed_and_hostile_split_is_content() -> void:
	assert_eq(DomainRoles.is_valid(&"mob"), true, "mob is a role")
	assert_eq(DomainRoles.is_valid(&"dragon"), false, "the role set is closed")
	assert_eq(DomainRoles.is_hostile(&"boss"), true, "a boss is hostile")
	assert_eq(DomainRoles.is_hostile(&"npc"), false, "an npc is not hostile on sight")
	assert_eq(
		DomainRoles.is_hostile(&"rival_cultivator"), false, "a rival is neutral until claimed"
	)
	assert_eq(
		DomainRoles.cultivates(&"rival_cultivator"), true, "a rival cultivator is a cultivator"
	)


# ── AC3: spawn refs resolve and are canonical ────────────────────────────────


func test_spawn_refs_are_canonical_and_carry_a_role() -> void:
	var refs := handcrafted_map().spawn_refs()
	assert_eq(refs.size(), 1, "one authored spawn ref")
	assert_eq(refs[0]["room_id"], "heart_of_ashes", "in the core room")
	assert_eq(refs[0]["role"], "boss", "with its role")
	assert_eq(refs[0]["inhabitant_id"], "ash_warden", "naming its inhabitant")


func test_spawn_refs_span_every_room_in_canonical_order() -> void:
	var refs := generated_map(7).spawn_refs()
	var rooms: Array[String] = []
	for ref in refs:
		rooms.append(ref["room_id"])
	assert_eq(rooms, ["hall", "vault"] as Array[String], "canonical room order")


func test_zones_are_flattened_and_carry_their_room() -> void:
	var map := handcrafted_map()
	map.room(&"ember_flue").environment_zones = (
		[_zone(&"furnace", &"super_hot")] as Array[EnvironmentZoneDef]
	)
	var zones := map.zones()
	assert_eq(zones.size(), 1, "one zone")
	assert_eq(zones[0]["room_id"], "ember_flue", "flattened with its owning room")
	assert_eq(zones[0]["kind"], "super_hot", "and its kind")


# ── room bands ───────────────────────────────────────────────────────────────


func test_room_kind_decides_the_default_band() -> void:
	assert_eq(RoomDef.default_band_for(&"core"), &"boss", "a core is a boss by definition")
	assert_eq(RoomDef.default_band_for(&"settlement"), &"social", "a settlement is social")
	assert_eq(RoomDef.default_band_for(&"corridor"), &"traffic", "a corridor is traffic")
	assert_eq(RoomDef.default_band_for(&"arena"), &"trial", "an arena is a trial")


func test_band_override_wins_over_kind_default() -> void:
	var room := _room(&"quiet", &"chamber", [] as Array[StringName])
	assert_eq(room.band(), &"contact", "the kind default")
	room.roster_band = &"empty"
	assert_eq(room.band(), &"empty", "an authored override wins")


func test_non_hostile_rooms_are_empty_or_social() -> void:
	var room := _room(&"r", &"settlement", [] as Array[StringName])
	assert_eq(room.is_hostile(), false, "a settlement holds npcs, not hostiles")
	room.kind = &"arena"
	assert_eq(room.is_hostile(), true, "an arena is a fight")


# ── helpers ──────────────────────────────────────────────────────────────────


func _contains(problems: PackedStringArray, needle: String) -> bool:
	for problem in problems:
		if problem.find(needle) >= 0:
			return true
	return false
