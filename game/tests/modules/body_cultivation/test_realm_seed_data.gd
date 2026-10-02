extends TestCase

## ADR 0023: the generated body-cultivation data layer — realm seeds, acupoint
## definitions, and the meridian refinement depth they drive.


func _actor() -> Actor:
	var actor := Actor.new(&"body_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	return actor


## Bring a channel all the way to strengthened at the depth the seed demands.
func _fully_train(actor: Actor, meridian_id: StringName, required_refinement: int) -> void:
	actor.meridians.open_meridian(meridian_id)
	actor.meridians.expand_meridian(meridian_id)
	actor.meridians.strengthen_meridian(meridian_id)
	var guard := 0
	while actor.meridians.refine_meridian(meridian_id, required_refinement) and guard < 16:
		guard += 1


# --- Realm seeds -----------------------------------------------------------


func test_every_realm_has_a_seed() -> void:
	for realm in RealmDefaults.ladder().realms():
		assert_eq(BodyRealmSeed.for_realm(realm.id) != null, true, "seed exists for %s" % realm.id)


func test_seed_defines_both_items_and_meridians() -> void:
	var seed := BodyRealmSeed.for_realm(&"qi_refining")
	assert_eq(seed != null, true, "seed loaded")
	assert_ne(seed.breakthrough_item, &"", "has breakthrough item")
	assert_ne(seed.strengthening_item, &"", "has strengthening item")
	assert_eq(seed.required_meridians.is_empty(), false, "requires meridians")


func test_seed_meridians_resolve_in_the_network() -> void:
	var known: Array[StringName] = []
	for def in MeridianDefaults.all():
		known.append(def.id)
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for meridian_id in seed.required_meridians:
			assert_eq(known.has(meridian_id), true, "meridian %s exists" % meridian_id)


func test_seed_items_resolve_in_content() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for item_id in [seed.breakthrough_item, seed.strengthening_item]:
			var path := "res://data/items/consumable/%s.tres" % item_id
			assert_eq(ResourceLoader.exists(path), true, "item %s exists" % item_id)


# --- Acupoint definitions --------------------------------------------------


func test_acupoint_definitions_load() -> void:
	assert_eq(AcupointDefaults.definitions().size(), 60, "60 generated acupoint definitions")


func test_build_for_realm_scales_with_tier() -> void:
	assert_eq(AcupointDefaults.build_for_realm(&"qi_refining").size(), 36, "36 minor at Mortal")
	# Major points unlock at index 9, the first Spirit realm.
	assert_eq(
		AcupointDefaults.build_for_realm(&"spirit_condensation").size(), 48, "plus major at Spirit"
	)
	assert_eq(
		AcupointDefaults.build_for_realm(&"earth_immortal").size(), 57, "plus celestial at Immortal"
	)
	assert_eq(
		AcupointDefaults.build_for_realm(&"transcendent").size(), 60, "all 60 at Transcendent"
	)


func test_acupoint_meridian_lookup() -> void:
	assert_eq(AcupointDefaults.meridian_of(&"minor_0"), &"lung", "minor_0 trains lung")
	assert_eq(AcupointDefaults.meridian_of(&"nonexistent"), &"", "unknown id has no meridian")


func test_synchronize_adds_newly_unlocked_points() -> void:
	var points := AcupointSet.new()
	points.synchronize(&"qi_refining")
	assert_eq(points.points.size(), 36, "minor only at Mortal")
	points.synchronize(&"spirit_condensation")
	assert_eq(points.points.size(), 48, "major added at Spirit")


func test_synchronize_is_idempotent() -> void:
	var points := AcupointSet.new()
	points.synchronize(&"qi_refining")
	points.synchronize(&"qi_refining")
	assert_eq(points.points.size(), 36, "no duplicate points")


func test_synchronize_preserves_quality_and_blocked() -> void:
	var points := AcupointSet.new()
	points.synchronize(&"qi_refining")
	var point := points.points[0]
	point.quality = 0.8
	point.block()
	points.synchronize(&"qi_refining")
	assert_almost_eq(point.quality, 0.8, "quality preserved")
	assert_eq(point.blocked, true, "blocked flag preserved")


# --- Meridian refinement ---------------------------------------------------


func test_refine_requires_strengthened_state() -> void:
	var actor := _actor()
	actor.meridians.open_meridian(&"lung")
	assert_eq(actor.meridians.refine_meridian(&"lung", 3), false, "cannot refine an open channel")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	assert_eq(actor.meridians.refine_meridian(&"lung", 3), true, "refine strengthened channel")


func test_refine_respects_cap() -> void:
	var actor := _actor()
	_fully_train(actor, &"lung", 0)
	assert_eq(actor.meridians.get_meridian(&"lung").refinement, 0, "zero cap allows no depth")
	assert_eq(actor.meridians.refine_meridian(&"lung", 2), true, "first refine")
	assert_eq(actor.meridians.refine_meridian(&"lung", 2), true, "second refine")
	assert_eq(actor.meridians.refine_meridian(&"lung", 2), false, "cap reached")


func test_refinement_raises_power_bonus() -> void:
	var actor := _actor()
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	var before := actor.meridians.get_power_bonus()
	actor.meridians.refine_meridian(&"lung", 3)
	assert_eq(actor.meridians.get_power_bonus() > before, true, "refinement adds power")


func test_refinement_round_trips_in_saves() -> void:
	var actor := _actor()
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.meridians.refine_meridian(&"lung", 3)
	actor.meridians.refine_meridian(&"lung", 3)
	var restored := Actor.from_dict(actor.to_dict())
	var channel := restored.meridians.get_meridian(&"lung")
	assert_eq(channel != null, true, "meridian restored")
	assert_eq(channel.refinement, 2, "refinement depth restored")
