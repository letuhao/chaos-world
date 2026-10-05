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


# --- Facade: recover_next --------------------------------------------------
#
# `MindTraining.recover` takes a channel id, so nothing outside this module could
# reach it: the mind panel had no way to offer the recovery the path's own data
# authors. `recover_next` is the verb that scans for the wound and is the shape
# `BodyCultivationApi.recover_next` and `QiCultivationApi.recover_next` already
# publish.
#
# The elixir COUNT is asserted, not the return value. `recover` returns true only
# AFTER `consume_item` succeeds, so a guard that stopped consuming the item would
# still close the wound and still return true; only the count sees it. That is why
# the count is derived from the inventory read rather than hardcoded to 0.


func test_recover_next_repairs_the_burned_channel() -> void:
	var actor := _actor()
	var burned := _first_unlocked(actor)
	actor.meridians.damage_meridian(burned)
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "channel burned")
	_stock(actor, _recovery_id())
	assert_eq(MindCultivationApi.recover_next(actor), true, "recovered")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "channel repaired")


## One elixir, one repair: `recover_next` closes ONE channel per call, so the
## count drops by exactly one no matter how many channels are burned. A guard that
## consumed zero (or spent the elixir without repairing) fails here.
func test_recover_next_consumes_exactly_one_elixir() -> void:
	var actor := _actor()
	var first := _first_unlocked(actor)
	var second := _second_unlocked(actor)
	actor.meridians.damage_meridian(first)
	actor.meridians.damage_meridian(second)
	# Two elixirs stocked: the assertion below distinguishes "one spent" from
	# "none spent" AND from "one spent per burned channel".
	_stock(actor, _recovery_id())
	_stock(actor, _recovery_id())
	var stocked := ItemsApi.inventory(actor).count(_recovery_id())
	assert_eq(stocked, 2, "two elixirs stocked")
	assert_eq(MindCultivationApi.recover_next(actor), true, "recovered")
	assert_eq(
		ItemsApi.inventory(actor).count(_recovery_id()), stocked - 1, "exactly one elixir consumed"
	)
	# One call, one wound: the second channel is still burned.
	assert_eq(actor.meridians.get_meridian(second).is_injured(), true, "second wound open")


## The negative case. `recover_next` refuses without the elixir and, critically,
## spends nothing and closes nothing -- a refusal that consumed the item would be
## the worst shape here, and the count assertion is what catches it.
func test_recover_next_refuses_without_the_elixir() -> void:
	var actor := _actor()
	var burned := _first_unlocked(actor)
	actor.meridians.damage_meridian(burned)
	assert_eq(MindCultivationApi.recover_next(actor), false, "no elixir, no recovery")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "still injured")
	assert_eq(ItemsApi.inventory(actor).count(_recovery_id()), 0, "nothing was spent")


## A healthy actor has no wound to find, so the facade is a no-op even holding
## elixirs. This is the "returns true for a real recovery" half of the contract:
## a screen must be able to tell a repair from a no-op.
func test_recover_next_is_a_noop_on_a_healthy_actor() -> void:
	var actor := _actor()
	_stock(actor, _recovery_id())
	assert_eq(MindCultivationApi.recover_next(actor), false, "nothing to repair")
	assert_eq(ItemsApi.inventory(actor).count(_recovery_id()), 1, "item not consumed on a no-op")


## The scan is `MeridianDefaults.all()` order, so the facade repairs the FIRST
## authored burned channel, not an arbitrary one. Derived from the code under
## test rather than pinned to a literal id.
func test_recover_next_repairs_the_first_authored_wound() -> void:
	var actor := _actor()
	var first := _first_unlocked(actor)
	var second := _second_unlocked(actor)
	actor.meridians.damage_meridian(second)
	actor.meridians.damage_meridian(first)
	_stock(actor, _recovery_id())
	assert_eq(MindCultivationApi.recover_next(actor), true, "recovered")
	assert_eq(
		actor.meridians.get_meridian(first).is_injured(),
		false,
		"the earlier authored channel is the one closed"
	)
	assert_eq(actor.meridians.get_meridian(second).is_injured(), true, "later wound untouched")


## The first two channels this actor's realm has actually unlocked. `recover_next`
## skips a channel the network does not carry, so the wound has to be on one that
## exists -- derived from `MeridianDefaults.all()` plus the live network.
func _first_unlocked(actor: Actor) -> StringName:
	return _unlocked(actor)[0]


func _second_unlocked(actor: Actor) -> StringName:
	return _unlocked(actor)[1]


func _unlocked(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in MeridianDefaults.all():
		if actor.meridians.get_meridian(def.id) != null:
			out.append(def.id)
	return out


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
