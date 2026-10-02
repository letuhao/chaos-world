extends TestCase

## ADR 0031: the mind-cultivation recovery consumable. A mind deviation clouds
## the sea (turbulence + halved clarity) and burns a channel; both are
## recoverable overlays, so every realm must author a `recovery_item` that
## `MindTraining.recover` spends.

const PATH := MindPath.PATH_ID


func _actor() -> Actor:
	var actor := Actor.new(
		&"mind_recovery", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 64)
	MindTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


func _recovery_id() -> StringName:
	return MindRealmSeed.for_realm(&"qi_refining").recovery_item


func test_recover_calms_a_clouded_sea() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.5)
	assert_eq(sea.turbulence > 0.0, true, "sea clouded")
	_stock(actor, _recovery_id())
	assert_eq(MindTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(sea.turbulence, 0.0, "turbulence calmed")


func test_recover_repairs_a_burned_channel() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, _recovery_id())
	assert_eq(MindTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "channel repaired")


func test_recover_requires_the_recovery_item() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	assert_eq(MindTraining.recover(actor, &"lung"), false, "no item, no recovery")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), true, "still injured")


func test_recover_is_a_noop_on_a_healthy_actor() -> void:
	var actor := _actor()
	_stock(actor, _recovery_id())
	assert_eq(MindTraining.recover(actor, &"lung"), false, "nothing to repair")
	assert_eq(ItemsApi.inventory(actor).count(_recovery_id()), 1, "item not consumed on a no-op")


func test_recover_rejects_an_unknown_channel() -> void:
	var actor := _actor()
	MindCultivationApi.sea(actor).add_turbulence(0.5)
	_stock(actor, _recovery_id())
	assert_eq(MindTraining.recover(actor, &"not_a_meridian"), false, "unknown channel")
	assert_eq(MindCultivationApi.sea(actor).turbulence > 0.0, true, "sea untouched")


func test_recover_restores_clarity_to_the_realm_floor() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	var floor := MindRealmSeed.for_realm(&"qi_refining").clarity_required
	sea.set_clarity(maxf(floor, 0.9))
	sea.add_turbulence(0.5)
	sea.set_clarity(0.1)
	_stock(actor, _recovery_id())
	assert_eq(MindTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(sea.clarity >= floor, true, "clarity back at the realm floor")


func test_every_mind_realm_authors_all_consumables() -> void:
	for def in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		assert_ne(seed.breakthrough_item, &"", "breakthrough item for %s" % def.id)
		assert_ne(seed.training_item, &"", "training item for %s" % def.id)
		assert_ne(seed.sea_catalyst, &"", "sea catalyst for %s" % def.id)
		assert_ne(seed.recovery_item, &"", "recovery item for %s" % def.id)


func test_every_mind_consumable_resolves_to_real_content() -> void:
	for def in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		for item_id in [
			seed.breakthrough_item, seed.training_item, seed.sea_catalyst, seed.recovery_item
		]:
			var found := Crafting.resolve(item_id)
			assert_ne(found, null, "%s exists" % item_id)
			if found != null:
				assert_eq(found.category, &"consumable", "%s is a consumable" % item_id)
