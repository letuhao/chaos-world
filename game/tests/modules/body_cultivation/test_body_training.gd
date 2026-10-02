extends TestCase

## ADR 0023: the body-cultivation action layer — training acupoints and channels,
## and the realm-seeded breakthrough that consumes them.


func _actor() -> Actor:
	var actor := Actor.new(&"body_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


## Bring a channel all the way to strengthened at the depth the seed demands.
func _fully_train(actor: Actor, meridian_id: StringName, required_refinement: int) -> void:
	# A deviation damages a required channel. open/expand/strengthen all require
	# an exact prior state, so a damaged channel must be repaired first or the
	# breakthrough precondition can never be met again.
	if actor.meridians.get_meridian(meridian_id).is_injured():
		actor.meridians.repair_meridian(meridian_id)
	actor.meridians.open_meridian(meridian_id)
	actor.meridians.expand_meridian(meridian_id)
	actor.meridians.strengthen_meridian(meridian_id)
	var guard := 0
	while actor.meridians.refine_meridian(meridian_id, required_refinement) and guard < 16:
		guard += 1


## Satisfy every gate the target realm's seed declares.
func _prepare_for_next_realm(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	# Channels must exist on the network before they can be trained.
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.strengthening_item)
	for meridian_id in seed.required_meridians:
		_fully_train(actor, meridian_id, seed.required_refinement)
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	# Fill the shared pool to maximum.
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	# The insight floor is reached by meditating, never by writing the stat.
	var guard := 0
	while guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required:
		guard += 1
		BodyTraining.meditate(actor, 1.0)
	return seed


# --- Item facade -----------------------------------------------------------


func test_items_has_and_consume() -> void:
	var actor := _actor()
	_stock(actor, &"body_qi_refining_breakthrough_pill")
	assert_eq(ItemsApi.has_item(actor, &"body_qi_refining_breakthrough_pill"), true, "has item")
	assert_eq(ItemsApi.has_item(actor, &"absent_item"), false, "missing item")
	assert_eq(ItemsApi.consume_item(actor, &"body_qi_refining_breakthrough_pill"), true, "consumed")
	assert_eq(
		ItemsApi.has_item(actor, &"body_qi_refining_breakthrough_pill"), false, "consumed gone"
	)


func test_consume_missing_item_is_a_noop() -> void:
	assert_eq(ItemsApi.consume_item(_actor(), &"absent_item"), false, "cannot consume absent item")


# --- Cultivation -----------------------------------------------------------


func test_cultivate_stores_essence_and_progress() -> void:
	var actor := _actor()
	assert_eq(BodyTraining.cultivate(actor, 50.0), true, "cultivation applied")
	assert_eq(actor.path(BodyPath.PATH_ID).progress > 0.0, true, "progress grew")
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.current() > 0.0, true, "essence stored in the shared pool")


func test_cultivate_raises_quality_toward_target() -> void:
	var actor := _actor()
	var points := BodyCultivationApi.acupoints(actor)
	points[0].quality = 0.0
	BodyTraining.cultivate(actor, 500.0)
	assert_eq(points[0].quality > 0.0, true, "quality trained upward")


func test_cultivate_rejects_busy_set() -> void:
	var actor := _actor()
	var points: AcupointSet = actor.component(&"acupoints")
	points.busy = true
	assert_eq(BodyTraining.cultivate(actor, 10.0), false, "blocked while busy")


# --- Channel training ------------------------------------------------------


func test_strengthen_advances_channel_state() -> void:
	var actor := _actor()
	_stock(actor, &"body_qi_refining_channel_elixir")
	assert_eq(BodyTraining.strengthen(actor, &"lung"), true, "lung trained")
	assert_eq(actor.meridians.get_meridian(&"lung").state, &"open", "now open")


func test_strengthen_requires_the_elixir() -> void:
	assert_eq(BodyTraining.strengthen(_actor(), &"lung"), false, "no elixir, no training")


func test_strengthen_rejects_unknown_channel() -> void:
	var actor := _actor()
	_stock(actor, &"body_qi_refining_channel_elixir")
	assert_eq(BodyTraining.strengthen(actor, &"not_a_meridian"), false, "unknown channel")


func test_strengthen_walks_the_full_channel_ladder() -> void:
	var actor := _actor()
	var seed := BodyRealmSeed.for_realm(&"foundation")
	var meridian_id := seed.required_meridians[0]
	var expected := [&"open", &"expanded", &"strengthened"]
	for want in expected:
		_stock(actor, &"body_qi_refining_channel_elixir")
		assert_eq(BodyTraining.strengthen(actor, meridian_id), true, "advanced to %s" % want)
		assert_eq(actor.meridians.get_meridian(meridian_id).state, want, "state is %s" % want)


# --- Recovery (third consumable role, ADR 0015/0023) ------------------------


func test_recover_clears_a_blocked_acupoint() -> void:
	var actor := _actor()
	var points := BodyCultivationApi.acupoints(actor)
	var meridian_id := AcupointDefaults.meridian_of(points[0].id)
	points[0].block()
	_stock(actor, &"body_qi_refining_recovery_elixir")
	assert_eq(BodyTraining.recover(actor, meridian_id), true, "blocked huyệt repaired")
	assert_eq(points[0].blocked, false, "blockage cleared")


func test_recover_repairs_an_injured_channel() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, &"body_qi_refining_recovery_elixir")
	assert_eq(BodyTraining.recover(actor, &"lung"), true, "injured channel repaired")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "injury cleared")


func test_recover_requires_the_recovery_item() -> void:
	var actor := _actor()
	BodyCultivationApi.acupoints(actor)[0].block()
	assert_eq(BodyTraining.recover(actor, &"lung"), false, "no recovery item, no repair")
	assert_eq(BodyCultivationApi.acupoints(actor)[0].blocked, true, "blockage untouched")


func test_recover_is_a_noop_on_a_healthy_channel() -> void:
	var actor := _actor()
	_stock(actor, &"body_qi_refining_recovery_elixir")
	assert_eq(BodyTraining.recover(actor, &"lung"), false, "nothing to repair")
	assert_eq(
		ItemsApi.inventory(actor).count(&"body_qi_refining_recovery_elixir"),
		1,
		"item not consumed on a no-op"
	)


func test_every_realm_authors_all_three_consumables() -> void:
	for def in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		assert_ne(seed.breakthrough_item, &"", "breakthrough item for %s" % def.id)
		assert_ne(seed.strengthening_item, &"", "strengthening item for %s" % def.id)
		assert_ne(seed.recovery_item, &"", "recovery item for %s" % def.id)


# --- Breakthrough ----------------------------------------------------------


func test_breakthrough_blocked_before_requirements() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(BodyAdvancement.try_breakthrough(actor, rng), false, "blocked when unprepared")


func test_breakthrough_condition_reports_requirements() -> void:
	var actor := _actor()
	var condition := BodyBreakthroughCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(BodyPath.PATH_ID), {}), false, "not ready yet"
	)
	assert_ne(condition.describe(), "", "condition describes itself")


func test_breakthrough_condition_passes_once_prepared() -> void:
	var actor := _actor()
	assert_ne(_prepare_for_next_realm(actor), null, "seed loaded")
	var condition := BodyBreakthroughCondition.new()
	assert_eq(condition.can_breakthrough(actor, actor.path(BodyPath.PATH_ID), {}), true, "ready")


## Re-prepare and roll until the actor advances. Seeds are swept so the outcome
## never depends on one unlucky stream; the preparation between attempts is the
## recovery a deviation requires.
func _advance(actor: Actor, attempts: int = 32) -> BodyRealmSeed:
	var rng := RandomNumberGenerator.new()
	var seed := _prepare_for_next_realm(actor)
	for attempt in attempts:
		if seed == null:
			break
		rng.seed = attempt + 1
		if BodyAdvancement.try_breakthrough(actor, rng):
			return seed
		seed = _prepare_for_next_realm(actor)
	return null


func test_breakthrough_succeeds_when_prepared() -> void:
	var actor := _actor()
	var state := actor.path(BodyPath.PATH_ID)
	assert_ne(_advance(actor), null, "breakthrough eventually succeeded")
	assert_ne(state.rank_id, &"qi_refining", "realm advanced")


func test_breakthrough_consumes_the_pill() -> void:
	var actor := _actor()
	var seed := _advance(actor)
	assert_ne(seed, null, "breakthrough succeeded")
	# The preparation before each roll stocks exactly one pill, so a successful
	# advance must leave none behind.
	assert_eq(ItemsApi.has_item(actor, seed.breakthrough_item), false, "pill consumed on success")


func test_deviation_blocks_an_acupoint_and_damages_a_channel() -> void:
	# Drive attempts until a deviation lands. A success would advance the realm,
	# so every attempt gets a fresh actor and only the first deviation is kept.
	# Seeds are swept so the outcome never depends on one unlucky stream.
	var rng := RandomNumberGenerator.new()
	var deviated := false
	var seed: BodyRealmSeed = null
	for attempt in 64:
		var actor := _actor()
		seed = _prepare_for_next_realm(actor)
		if seed == null:
			break
		var start_rank := actor.path(BodyPath.PATH_ID).rank_id
		rng.seed = attempt + 1
		if BodyAdvancement.try_breakthrough(actor, rng):
			continue
		assert_eq(actor.path(BodyPath.PATH_ID).rank_id, start_rank, "deviation changed no realm")
		var blocked := false
		for point in BodyCultivationApi.acupoints(actor):
			if point.blocked:
				blocked = true
		var channel_damaged := false
		for meridian_id in seed.required_meridians:
			if actor.meridians.get_meridian(meridian_id).is_injured():
				channel_damaged = true
		deviated = blocked and channel_damaged
		if deviated:
			# The deviation is recoverable: a fresh preparation clears it again.
			assert_ne(_prepare_for_next_realm(actor), null, "prepared again after the deviation")
			for point in BodyCultivationApi.acupoints(actor):
				assert_eq(point.blocked, false, "blockage of %s cleared" % point.id)
			for meridian_id in seed.required_meridians:
				assert_eq(
					actor.meridians.get_meridian(meridian_id).is_injured(),
					false,
					"injury of %s repaired" % meridian_id
				)
			break
	assert_eq(deviated, true, "a deviation blocked a point and damaged a channel")
