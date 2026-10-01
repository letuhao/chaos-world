extends TestCase

## ADR 0024: the qi-cultivation action layer — refining the dantian, training a
## meridian, and the seeded breakthrough that spends the pill.


func _actor() -> Actor:
	var actor := Actor.new(&"qi_hero", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	# A roomy inventory: repeated attempts re-stock both items each roll.
	ItemsApi.attach(actor, 200)
	QiTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


func _prepare(actor: Actor) -> QiRealmSeed:
	var state := actor.path(QiPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.training_item)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		# A deviation damages a channel, and a damaged channel satisfies nothing,
		# so repair before re-training or the next attempt can never qualify.
		actor.meridians.repair_meridian(meridian_id)
		if not channel.is_open():
			actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
	var dantian := QiCultivationApi.dantian(actor)
	dantian.capacity = seed.dantian_capacity
	dantian.quality = seed.dantian_quality_required
	dantian.drain(dantian.current)
	dantian.fill(dantian.effective_capacity())
	state.progress = seed.progress_required
	return seed


# --- Synchronize -----------------------------------------------------------


func test_synchronize_sets_capacity_tier_and_unlocks() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	assert_eq(dantian != null, true, "dantian attached")
	assert_eq(dantian.tier, &"lower", "Mortal uses the lower dantian")
	assert_almost_eq(dantian.capacity, 100.0, "capacity from the seed")


func test_synchronize_scales_capacity_with_meridian_bonus() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	var base := dantian.capacity
	QiTraining.synchronize(actor)
	assert_eq(dantian.capacity > base, true, "expanded channels widen the dantian")


func test_synchronize_clamps_stored_qi() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	dantian.fill(dantian.effective_capacity())
	QiTraining.synchronize(actor)
	assert_almost_eq(dantian.current, dantian.effective_capacity(), "full dantian stays full")


# --- Cultivation -----------------------------------------------------------


func test_cultivate_fills_the_dantian_and_advances_progress() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	dantian.drain(dantian.current)
	assert_eq(QiTraining.cultivate(actor, 50.0), true, "cultivation applied")
	assert_eq(dantian.current > 0.0, true, "qi stored")
	assert_eq(actor.path(QiPath.PATH_ID).progress > 0.0, true, "progress grew")


func test_cultivate_refines_dantian_quality() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	dantian.quality = 0.0
	QiTraining.cultivate(actor, 500.0)
	assert_eq(dantian.quality > 0.0, true, "quality refined by circulation")


func test_cultivate_stops_when_the_dantian_is_full() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	dantian.fill(dantian.effective_capacity())
	assert_eq(QiTraining.cultivate(actor, 10.0), false, "refuses a full dantian")


func test_cultivate_rejects_nonpositive_amount() -> void:
	var actor := _actor()
	assert_eq(QiTraining.cultivate(actor, 0.0), false, "zero refused")
	assert_eq(QiTraining.cultivate(actor, -5.0), false, "negative refused")


# --- Channel training ------------------------------------------------------


func test_train_channel_walks_the_ladder() -> void:
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.training_item)
	assert_eq(QiTraining.train_channel(actor, &"lung"), true, "lung opened")
	assert_eq(actor.meridians.get_meridian(&"lung").state, MeridianState.OPEN, "now open")


func test_train_channel_requires_the_elixir() -> void:
	assert_eq(QiTraining.train_channel(_actor(), &"lung"), false, "no elixir, no training")


func test_train_channel_rejects_unknown_channel() -> void:
	var actor := _actor()
	_stock(actor, QiRealmSeed.for_realm(&"qi_refining").training_item)
	assert_eq(QiTraining.train_channel(actor, &"not_a_meridian"), false, "unknown channel")


func test_train_channel_repairs_a_damaged_channel() -> void:
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, seed.training_item)
	assert_eq(QiTraining.train_channel(actor, &"lung"), true, "repaired")
	assert_eq(actor.meridians.get_meridian(&"lung").is_damaged(), false, "no longer damaged")


# --- Breakthrough ----------------------------------------------------------


func test_breakthrough_blocked_before_requirements() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_eq(QiAdvancement.try_breakthrough(actor, rng), false, "blocked when unprepared")


func test_breakthrough_condition_describes_itself() -> void:
	var actor := _actor()
	var condition := QiBreakthroughCondition.new()
	assert_eq(condition.can_breakthrough(actor, actor.path(QiPath.PATH_ID), {}), false, "not ready")
	assert_ne(condition.describe(), "", "condition describes itself")


func test_breakthrough_condition_passes_once_prepared() -> void:
	var actor := _actor()
	assert_ne(_prepare(actor), null, "seed loaded")
	var condition := QiBreakthroughCondition.new()
	assert_eq(condition.can_breakthrough(actor, actor.path(QiPath.PATH_ID), {}), true, "ready")


func test_breakthrough_succeeds_and_advances() -> void:
	var actor := _actor()
	var state := actor.path(QiPath.PATH_ID)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var succeeded := false
	for _attempt in 30:
		if _prepare(actor) == null:
			break
		if QiAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough eventually succeeded")
	assert_ne(state.rank_id, &"qi_refining", "realm advanced")


func test_breakthrough_consumes_the_pill() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var succeeded := false
	var pill: StringName = &""
	for _attempt in 30:
		var seed := _prepare(actor)
		if seed == null:
			break
		pill = seed.breakthrough_item
		if QiAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough succeeded")
	assert_eq(ItemsApi.has_item(actor, pill), false, "pill consumed")


func test_deviation_scares_the_dantian_and_damages_a_channel() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "seed loaded")
	var state := actor.path(QiPath.PATH_ID)
	var start_rank := state.rank_id
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Rolls are not forced, so keep re-preparing until one deviates. A success
	# only moves the target realm; it does not invalidate the search.
	var deviated := false
	var attempts := 0
	while attempts < 40 and not deviated:
		attempts += 1
		var current := _prepare(actor)
		if current == null:
			break
		if QiAdvancement.try_breakthrough(actor, rng):
			continue
		var dantian := QiCultivationApi.dantian(actor)
		var channel_damaged := false
		for meridian_id in current.required_meridians:
			if actor.meridians.get_meridian(meridian_id).is_damaged():
				channel_damaged = true
		deviated = dantian.damaged and channel_damaged
	assert_eq(deviated, true, "deviation scarred the dantian and burned a channel")


func test_damaged_dantian_reduces_usable_capacity() -> void:
	var actor := _actor()
	var dantian := QiCultivationApi.dantian(actor)
	var full := dantian.effective_capacity()
	dantian.damage()
	assert_almost_eq(dantian.effective_capacity(), full * 0.75, "damage costs 25% capacity")
	dantian.heal()
	assert_almost_eq(dantian.effective_capacity(), full, "healing restores capacity")
