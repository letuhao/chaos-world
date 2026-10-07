extends TestCase

## ADR 0031: the qi-cultivation recovery consumable. A qi deviation scars the
## dantian and burns a channel; both are recoverable overlays, so every realm
## must author a `recovery_item` that `QiTraining.recover` spends.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")


func _actor() -> Actor:
	var actor := Actor.new(&"qi_hero", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 400)
	QiTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	assert_eq(Probe.stock(actor, def_id, 1), true, "authored item %s stocked" % def_id)


func _recovery_id() -> StringName:
	return QiRealmSeed.for_realm(&"qi_refining").recovery_item


## Train every channel the target realm demands to its gate, through the public
## verb, so the injury is the *only* remaining blocker. Without this a "refused"
## assertion would pass for the wrong reason and prove nothing. It used to hand-open
## each channel instead, which stopped discriminating the moment the ladder began
## to demand depth as well as state (ADR 0095).
func _open_required_channels(actor: Actor, seed: QiRealmSeed) -> void:
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for %s" % seed.id)


## A scar must be healed, not merely refilled. `Dantian.damage` drops usable
## capacity to 75% and clamps the reservoir down with it, so an injured dantian
## refills to a full ratio again — and the breakthrough gate used to accept that,
## while `preview` correctly reported `dantian_injured`. Preview and execute must
## agree: this is the test that fails without the `_dantian_ready` injury check.
func test_a_scarred_dantian_cannot_be_spent_on_a_breakthrough() -> void:
	var actor := _actor()
	var dantian := QiTestKit.dantian(actor)
	var target := RealmDefaults.ladder().next(&"qi_refining")
	var seed := QiRealmSeed.for_realm(target.id)
	_open_required_channels(actor, seed)
	_stock(actor, seed.breakthrough_item)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.damage(actor)
	# Refill to the reduced capacity, so only the injury can be blocking. The work
	# budget is earned rather than assigned: this test claims the injury is the ONLY
	# unmet condition, so every other gate has to be genuinely met.
	dantian.fill(actor, dantian.effective_capacity())
	QiTraining.synchronize(actor)
	assert_eq(Probe.earn_progress(actor, seed), true, "the work budget was earned, not written")
	assert_eq(dantian.injured, true, "scarred")
	assert_eq(dantian.ratio(actor), 1.0, "refilled to its reduced capacity")
	assert_eq(
		str(QiBreakthroughTransaction.preview(actor)["unmet_conditions"]),
		'["dantian_injured"]',
		"the injury is the only unmet condition"
	)
	assert_eq(
		QiBreakthroughCondition.new().can_breakthrough(actor, actor.path(QiPath.PATH_ID), {}),
		false,
		"a scar blocks the attempt even at a full ratio"
	)
	assert_eq(QiCultivationApi.attempt_breakthrough(actor), false, "no advance")
	assert_eq(actor.path(QiPath.PATH_ID).rank_id, &"qi_refining", "realm unchanged")


## The same actor, healed, is spendable — so the refusal above is the scar and not
## some other gate quietly refusing.
func test_a_healed_dantian_is_spendable_again() -> void:
	var actor := _actor()
	var dantian := QiTestKit.dantian(actor)
	var target := RealmDefaults.ladder().next(&"qi_refining")
	var seed := QiRealmSeed.for_realm(target.id)
	_open_required_channels(actor, seed)
	_stock(actor, seed.breakthrough_item)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.damage(actor)
	dantian.fill(actor, dantian.effective_capacity())
	_stock(actor, _recovery_id())
	assert_eq(QiCultivationApi.recover_next(actor), true, "healed")
	dantian.fill(actor, dantian.effective_capacity())
	QiTraining.synchronize(actor)
	assert_eq(Probe.earn_progress(actor, seed), true, "the work budget was earned, not written")
	var condition := QiBreakthroughCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(QiPath.PATH_ID), {}),
		true,
		(
			"no unmet condition remains: %s"
			% str(QiBreakthroughTransaction.preview(actor)["unmet_conditions"])
		)
	)


func test_recover_heals_the_scarred_dantian() -> void:
	var actor := _actor()
	var dantian := QiTestKit.dantian(actor)
	dantian.damage(actor)
	assert_eq(dantian.injured, true, "dantian scarred")
	_stock(actor, _recovery_id())
	assert_eq(QiTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(dantian.injured, false, "dantian healed")


func test_recover_repairs_a_burned_channel() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, _recovery_id())
	assert_eq(QiTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "channel repaired")


func test_recover_requires_the_recovery_item() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	assert_eq(QiTraining.recover(actor, &"lung"), false, "no item, no recovery")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), true, "still injured")


func test_recover_is_a_noop_on_a_healthy_actor() -> void:
	var actor := _actor()
	_stock(actor, _recovery_id())
	assert_eq(QiTraining.recover(actor, &"lung"), false, "nothing to repair")
	assert_eq(ItemsApi.inventory(actor).count(_recovery_id()), 1, "item not consumed on a no-op")


func test_recover_rejects_an_unknown_channel() -> void:
	var actor := _actor()
	QiTestKit.dantian(actor).damage(actor)
	_stock(actor, _recovery_id())
	assert_eq(QiTraining.recover(actor, &"not_a_meridian"), false, "unknown channel")
	assert_eq(QiTestKit.dantian(actor).injured, true, "dantian untouched")


func test_recover_heals_structural_damage_but_leaves_quality_to_circulation() -> void:
	# `recover` repairs the injury flag; the quality a deviation halved is
	# retrained by `cultivate`, which is why the traversal test circulates again
	# after every recovery. It deliberately does *not* restore quality itself.
	var actor := _actor()
	var dantian := QiTestKit.dantian(actor)
	dantian.set_quality(0.8)
	dantian.damage(actor)
	dantian.set_quality(0.4)
	var quality_before := dantian.quality
	_stock(actor, _recovery_id())
	assert_eq(QiTraining.recover(actor, &"lung"), true, "recovered")
	assert_eq(dantian.injured, false, "no longer injured")
	assert_eq(dantian.effective_capacity() > 0.0, true, "dantian usable again")
	assert_eq(dantian.quality, quality_before, "quality is unchanged by recovery")


func test_meditate_is_the_only_route_to_the_comprehension_floor() -> void:
	var actor := _actor()
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	assert_eq(QiTraining.meditate(actor, 1.0), true, "meditated")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION) > before, true, "comprehension grew")
	assert_eq(QiTraining.meditate(actor, 0.0), false, "zero amount rejected")
	assert_eq(QiTraining.meditate(actor, -1.0), false, "negative amount rejected")


func test_comprehension_floor_is_reachable_through_meditation_alone() -> void:
	# Every realm's comprehension floor must be reachable by the public action.
	# Circulating qi refines the dantian but never teaches, and the realm rewards
	# grant `spirit` rather than comprehension, so without this the path dead-ends
	# partway up the ladder.
	var actor := _actor()
	for def in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		var guard := 0
		while (
			guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.comprehension_required
		):
			guard += 1
			QiTraining.meditate(actor, 1.0)
		assert_eq(
			actor.stats.get_base(Stat.COMPREHENSION) >= seed.comprehension_required,
			true,
			"floor reachable at %s" % def.id
		)


func test_every_qi_realm_authors_all_three_consumables() -> void:
	for def in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		assert_ne(seed.breakthrough_item, &"", "breakthrough item for %s" % def.id)
		assert_ne(seed.training_item, &"", "training item for %s" % def.id)
		assert_ne(seed.recovery_item, &"", "recovery item for %s" % def.id)


func test_every_qi_recovery_item_resolves_to_real_content() -> void:
	for def in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(def.id)
		if seed == null or seed.recovery_item == &"":
			continue
		var found := Crafting.resolve(seed.recovery_item)
		assert_ne(found, null, "recovery item %s exists" % seed.recovery_item)
		if found != null:
			assert_eq(found.category, &"consumable", "%s is a consumable" % seed.recovery_item)
