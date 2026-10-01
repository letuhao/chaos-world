extends TestCase

## ADR 0024: the generated mind-cultivation data contract — one realm seed per
## realm, and the channels and items each seed references.

# --- Seed data -------------------------------------------------------------


func test_every_realm_has_a_seed() -> void:
	for realm in RealmDefaults.ladder().realms():
		assert_eq(MindRealmSeed.for_realm(realm.id) != null, true, "seed for %s" % realm.id)


func test_seed_defines_both_items_and_channels() -> void:
	var seed := MindRealmSeed.for_realm(&"qi_refining")
	assert_eq(seed != null, true, "seed loaded")
	assert_ne(seed.breakthrough_item, &"", "has breakthrough item")
	assert_ne(seed.training_item, &"", "has training item")
	assert_eq(seed.required_meridians.is_empty(), false, "requires channels")


func test_seed_requires_strengthened_channels() -> void:
	# Mind cultivation reads channels only after they are fully trained
	# (ADR 0016), unlike qi which only needs them open.
	var seed := MindRealmSeed.for_realm(&"qi_refining")
	assert_eq(seed.required_channel_state, MeridianState.STRENGTHENED, "needs strengthened")


func test_seed_channels_exist_in_the_network() -> void:
	var known: Array[StringName] = []
	for def in MeridianDefaults.all():
		known.append(def.id)
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for meridian_id in seed.required_meridians:
			assert_eq(known.has(meridian_id), true, "channel %s exists" % meridian_id)


func test_seed_items_exist_in_content() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for item_id in [seed.breakthrough_item, seed.training_item]:
			var path := "res://data/items/consumable/%s.tres" % item_id
			assert_eq(ResourceLoader.exists(path), true, "item %s exists" % item_id)


func test_sea_tier_advances_with_realm() -> void:
	assert_eq(MindRealmSeed.for_realm(&"qi_refining").sea_tier, &"shallow", "Mortal is shallow")
	assert_eq(MindRealmSeed.for_realm(&"spirit_sea").sea_tier, &"deep", "Spirit is deep")
	assert_eq(MindRealmSeed.for_realm(&"earth_immortal").sea_tier, &"vast", "Immortal is vast")


func test_seed_never_requires_an_unopened_channel() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var network := MeridianNetwork.new()
		network.unlock_for_realm(realm.id)
		for meridian_id in seed.required_meridians:
			assert_eq(
				network.get_meridian(meridian_id) != null,
				true,
				"%s openable for %s" % [meridian_id, realm.id]
			)
