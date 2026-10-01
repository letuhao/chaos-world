extends TestCase

## ADR 0024: the generated qi-cultivation data contract — one realm seed per
## realm, and the meridians and items each seed references.


func _seed_for_next(actor: Actor) -> QiRealmSeed:
	var state := actor.path(QiPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	return QiRealmSeed.for_realm(target.id)


# --- Seed data -------------------------------------------------------------


func test_every_realm_has_a_seed() -> void:
	for realm in RealmDefaults.ladder().realms():
		assert_eq(QiRealmSeed.for_realm(realm.id) != null, true, "seed for %s" % realm.id)


func test_seed_defines_both_items_and_channels() -> void:
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	assert_eq(seed != null, true, "seed loaded")
	assert_ne(seed.breakthrough_item, &"", "has breakthrough item")
	assert_ne(seed.training_item, &"", "has training item")
	assert_eq(seed.required_meridians.is_empty(), false, "requires channels")


func test_seed_channels_exist_in_the_network() -> void:
	var known: Array[StringName] = []
	for def in MeridianDefaults.all():
		known.append(def.id)
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for meridian_id in seed.required_meridians:
			assert_eq(known.has(meridian_id), true, "channel %s exists" % meridian_id)


func test_seed_items_exist_in_content() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for item_id in [seed.breakthrough_item, seed.training_item]:
			var path := "res://data/items/consumable/%s.tres" % item_id
			assert_eq(ResourceLoader.exists(path), true, "item %s exists" % item_id)


func test_storage_tier_advances_with_realm() -> void:
	assert_eq(QiRealmSeed.for_realm(&"qi_refining").dantian_tier, &"lower", "Mortal is lower")
	assert_eq(QiRealmSeed.for_realm(&"spirit_sea").dantian_tier, &"middle", "Spirit is middle")
	assert_eq(QiRealmSeed.for_realm(&"earth_immortal").dantian_tier, &"upper", "Immortal is upper")


func test_seed_never_requires_an_unopened_channel() -> void:
	# A seed describes the realm being entered, so its required channels must
	# already be unlocked at the realm the actor is leaving.
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
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


# --- Channel state comparison ----------------------------------------------


func test_meets_compares_forward_states() -> void:
	var channel := MeridianState.new()
	channel.state = MeridianState.OPEN
	assert_eq(channel.meets(MeridianState.OPEN), true, "open meets open")
	assert_eq(channel.meets(MeridianState.EXPANDED), false, "open does not meet expanded")
	channel.state = MeridianState.EXPANDED
	assert_eq(channel.meets(MeridianState.OPEN), true, "expanded meets open")
	assert_eq(channel.meets(MeridianState.EXPANDED), true, "expanded meets expanded")
	channel.state = MeridianState.STRENGTHENED
	assert_eq(channel.meets(MeridianState.EXPANDED), true, "strengthened meets expanded")


func test_damaged_channel_meets_nothing() -> void:
	var channel := MeridianState.new()
	channel.state = MeridianState.DAMAGED
	assert_eq(channel.meets(MeridianState.CLOSED), false, "damaged never satisfies")
	assert_eq(channel.state_rank(), 0, "damaged ranks as closed")


func test_tier_gates_are_permissive_below_immortal() -> void:
	var actor := Actor.new(&"hero")
	# Index 0 targets the first Spirit realm: no tier gate applies yet.
	assert_eq(Breakthrough.tier_gates_met(actor, 0), true, "no gates at Mortal")
