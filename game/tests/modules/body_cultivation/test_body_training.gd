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
	if actor.meridians.get_meridian(meridian_id).is_damaged():
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
		point.fill(point.capacity)
	actor.change_resource(BodyStats.BODY_INTEGRITY, 100000.0)
	state.progress = seed.progress_required
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
	var stored := 0.0
	for point in BodyCultivationApi.acupoints(actor):
		stored += point.current
	assert_eq(stored > 0.0, true, "essence stored in acupoints")


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


func test_breakthrough_succeeds_when_prepared() -> void:
	var actor := _actor()
	var state := actor.path(BodyPath.PATH_ID)
	assert_ne(_prepare_for_next_realm(actor), null, "seed loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var succeeded := false
	for _attempt in 30:
		if BodyAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
		# A deviation consumed the pill and damaged the body; re-prepare and retry.
		_prepare_for_next_realm(actor)
	assert_eq(succeeded, true, "breakthrough eventually succeeded")
	assert_ne(state.rank_id, &"qi_refining", "realm advanced")


func test_breakthrough_consumes_the_pill() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var succeeded := false
	var pill: StringName = &""
	for _attempt in 30:
		# Re-stock before every roll, never before the loop: a deviation also
		# consumes the pill, so exactly one must be present when the advance
		# succeeds for the consumption to be observable.
		var seed := _prepare_for_next_realm(actor)
		if seed == null:
			break
		pill = seed.breakthrough_item
		if BodyAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough succeeded")
	assert_eq(ItemsApi.has_item(actor, pill), false, "pill consumed on success")


func test_deviation_blocks_an_acupoint_and_damages_a_channel() -> void:
	var actor := _actor()
	var seed := _prepare_for_next_realm(actor)
	assert_ne(seed, null, "seed loaded")
	var state := actor.path(BodyPath.PATH_ID)
	var start_rank := state.rank_id
	# Drive repeated attempts until a deviation lands, and stop at the first one:
	# a success would advance the realm and invalidate the assertions below.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attempts := 0
	var deviated := false
	while attempts < 30 and not deviated:
		_prepare_for_next_realm(actor)
		if BodyAdvancement.try_breakthrough(actor, rng):
			break
		var blocked := false
		for point in BodyCultivationApi.acupoints(actor):
			if point.blocked:
				blocked = true
		var channel_damaged := false
		for meridian_id in seed.required_meridians:
			if actor.meridians.get_meridian(meridian_id).is_damaged():
				channel_damaged = true
		deviated = blocked and channel_damaged
		attempts += 1
	assert_eq(deviated, true, "a deviation blocked a point and damaged a channel")
	assert_eq(state.rank_id, start_rank, "realm unchanged by the deviation")
