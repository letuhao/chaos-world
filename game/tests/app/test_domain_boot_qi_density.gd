extends TestCase

## ADR 0214 + ADR 0926: the PLACE side of the gain multiplier is published by the
## composition root at the two moments a room is entered (`_apply_zones`), and cleared on
## leaving the run. This is the seam `CultivationGain.publish_density` is written from —
## without it a zone's `qi_density` is a `.tres` row no run ever reads, which is the state
## DEF-0117 was deferred in.

const ROOM := &"density_room"


func _hero() -> Actor:
	var actor := ActorFactory.build(&"density_probe", {Stat.APTITUDE: 10.0})
	actor.attach_core_resources()
	ActorFactory.with_qi_cultivation(actor)
	return actor


func _zone(zone_id: StringName, density: float) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = zone_id
	zone.kind = &"verdant"
	zone.intensity = 1
	zone.status_id = &"env_scourge"
	zone.qi_density = density
	zone.mitigation_tags = [&"gear", &"affinity"] as Array[StringName]
	zone.bounds = Rect2i(0, 0, 2, 2)
	return zone


func _map_with(zones: Array[EnvironmentZoneDef]) -> DomainMap:
	var map := DomainMap.new(Vector2i(24, 18), 7)
	var room := RoomDef.new()
	room.room_id = ROOM
	room.kind = &"chamber"
	room.environment_zones = zones
	map.add_room(room)
	map.entry_room = ROOM
	return map


func test_a_room_publishes_its_richest_zone_density() -> void:
	var hero := _hero()
	var map := _map_with([_zone(&"thin", 0.9), _zone(&"rich", 1.2)] as Array[EnvironmentZoneDef])
	DomainBoot._apply_zones(hero, map, ROOM)
	assert_almost_eq(CultivationGain.density_of(hero), 1.2, "the richest zone answers for the room")


func test_a_room_without_zones_clears_a_stale_density() -> void:
	var hero := _hero()
	DomainBoot._apply_zones(
		hero, _map_with([_zone(&"rich", 1.2)] as Array[EnvironmentZoneDef]), ROOM
	)
	assert_almost_eq(CultivationGain.density_of(hero), 1.2, "a rich room first")
	DomainBoot._apply_zones(hero, _map_with([] as Array[EnvironmentZoneDef]), ROOM)
	assert_almost_eq(
		CultivationGain.density_of(hero),
		CultivationGain.NEUTRAL,
		"walking into a plain room clears it"
	)


func test_leaving_the_run_clears_the_density() -> void:
	var hero := _hero()
	CultivationGain.publish_density(hero, 1.2)
	var left := DomainBoot.leave_domain(hero)
	assert_eq(bool(left.get("ok", false)), false, "there was no run to leave, and that is fine")
	assert_almost_eq(
		CultivationGain.density_of(hero), CultivationGain.NEUTRAL, "the place goes with the run"
	)


## The room the zone was added to must keep everything else it carried: adding a zone is
## additive, and a `.tres` edit that silently dropped a spawn ref or a fixture would be a
## content loss nobody would see.
func test_the_ley_spring_room_keeps_its_other_content() -> void:
	var camp := load("res://src/data/domains/rooms/ash_camp.tres") as RoomDef
	assert_ne(camp, null, "the camp loads")
	if camp == null:
		return
	assert_eq(camp.actor_spawn_refs.size(), 2, "its two spawn refs survive")
	assert_eq(camp.fixtures.size(), 1, "and its treasure fixture")
	assert_eq(camp.environment_zones.size(), 1, "and the new zone")
	assert_eq(
		String(camp.environment_zones[0].zone_id), "ash_camp_ley_spring", "which is the ley spring"
	)


## The content half: a reward no room authors is a mechanic no player can reach. This
## scans the shipped room kit, so deleting the only rich zone fails here rather than in a
## playtest.
func test_the_authored_room_kit_keeps_a_rich_zone_in_band() -> void:
	var dir := DirAccess.open("res://src/data/domains/rooms")
	assert_ne(dir, null, "the room kit exists")
	if dir == null:
		return
	var rich := 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var room := load("res://src/data/domains/rooms/%s" % file) as RoomDef
		if room == null:
			continue
		for zone in room.environment_zones:
			assert_eq(
				(
					zone.qi_density >= CultivationGain.QI_DENSITY_MIN
					and zone.qi_density <= CultivationGain.QI_DENSITY_MAX
				),
				true,
				"%s/%s authors a density inside the band" % [file, zone.zone_id]
			)
			if zone.qi_density > CultivationGain.NEUTRAL:
				rich += 1
	assert_eq(rich > 0, true, "at least one authored zone is richer than neutral")
