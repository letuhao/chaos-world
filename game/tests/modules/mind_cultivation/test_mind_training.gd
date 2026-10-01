extends TestCase

## ADR 0024: the mind-cultivation action layer — filling the sea, meditating to
## calm turbulence, training a channel, and the seeded breakthrough.


func _actor() -> Actor:
	var actor := Actor.new(&"mind_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	# A roomy inventory: repeated attempts re-stock both items each roll.
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


## Mind demands strengthened channels, so drive each one all the way up.
func _prepare(actor: Actor) -> MindRealmSeed:
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := MindRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.training_item)
	for meridian_id in seed.required_meridians:
		# A deviation damages a channel, and a damaged channel satisfies nothing,
		# so repair before re-training or the next attempt can never qualify.
		actor.meridians.repair_meridian(meridian_id)
		if not actor.meridians.get_meridian(meridian_id).is_open():
			actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(seed.sea_capacity)
	sea.set_clarity(seed.clarity_required)
	sea.set_purity(seed.purity_required)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	MindTraining.synchronize(actor)
	sea.add_turbulence(-sea.turbulence)
	MindTraining.synchronize(actor)
	sea.drain(actor, sea.current(actor))
	sea.fill(actor, sea.effective_capacity())
	state.progress = seed.progress_required
	return seed


# --- Synchronize -----------------------------------------------------------


func test_synchronize_sets_capacity_and_tier() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	assert_eq(sea != null, true, "sea attached")
	assert_eq(sea.tier, &"shallow", "Mortal uses the shallow sea")
	assert_almost_eq(sea.structural_capacity, 100.0, "capacity from the seed")


func test_synchronize_scales_capacity_with_meridian_bonus() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	var base := sea.structural_capacity
	MindTraining.synchronize(actor)
	assert_eq(sea.structural_capacity > base, true, "expanded channels widen the sea")


# --- Cultivation and meditation --------------------------------------------


func test_cultivate_fills_the_sea_and_advances_progress() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.drain(actor, sea.current(actor))
	assert_eq(MindTraining.cultivate(actor, 50.0), true, "cultivation applied")
	assert_eq(sea.current(actor) > 0.0, true, "mind power stored")
	assert_eq(actor.path(MindPath.PATH_ID).progress > 0.0, true, "progress grew")


func test_cultivate_sharpens_clarity() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_clarity(0.0)
	MindTraining.cultivate(actor, 500.0)
	assert_eq(sea.clarity > 0.0, true, "clarity sharpened")


func test_cultivate_stops_when_the_sea_is_full() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.fill(actor, sea.effective_capacity())
	assert_eq(MindTraining.cultivate(actor, 10.0), false, "refuses a full sea")


func test_meditate_calms_turbulence() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.6)
	assert_eq(MindTraining.meditate(actor, 0.4), true, "meditation applied")
	assert_almost_eq(sea.turbulence, 0.2, "turbulence reduced")


func test_meditate_is_a_noop_when_calm() -> void:
	var actor := _actor()
	assert_eq(MindTraining.meditate(actor, 0.5), false, "nothing to calm")


# --- Channel training ------------------------------------------------------


func test_train_channel_walks_the_ladder() -> void:
	var actor := _actor()
	_stock(actor, MindRealmSeed.for_realm(&"qi_refining").training_item)
	assert_eq(MindTraining.train_channel(actor, &"lung"), true, "lung trained")
	assert_eq(actor.meridians.get_meridian(&"lung").state, MeridianState.OPEN, "now open")


func test_train_channel_requires_the_elixir() -> void:
	assert_eq(MindTraining.train_channel(_actor(), &"lung"), false, "no elixir, no training")


func test_train_channel_repairs_a_damaged_channel() -> void:
	var actor := _actor()
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, MindRealmSeed.for_realm(&"qi_refining").training_item)
	assert_eq(MindTraining.train_channel(actor, &"lung"), true, "repaired")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "no longer injured")


# --- Breakthrough ----------------------------------------------------------


func test_breakthrough_blocked_before_requirements() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), false, "blocked when unprepared")


func test_breakthrough_condition_describes_itself() -> void:
	var actor := _actor()
	var condition := MindBreakthroughCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(MindPath.PATH_ID), {}), false, "not ready"
	)
	assert_ne(condition.describe(), "", "condition describes itself")


func test_turbulent_sea_blocks_the_attempt() -> void:
	var actor := _actor()
	assert_ne(_prepare(actor), null, "seed loaded")
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.3)
	var condition := MindBreakthroughCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(MindPath.PATH_ID), {}),
		false,
		"turbulence must be calmed first"
	)
	sea.calm(1.0)
	assert_eq(
		condition.can_breakthrough(actor, actor.path(MindPath.PATH_ID), {}),
		true,
		"calm sea is ready"
	)


func test_breakthrough_condition_passes_once_prepared() -> void:
	var actor := _actor()
	assert_ne(_prepare(actor), null, "seed loaded")
	var condition := MindBreakthroughCondition.new()
	assert_eq(condition.can_breakthrough(actor, actor.path(MindPath.PATH_ID), {}), true, "ready")


func test_breakthrough_succeeds_and_advances() -> void:
	var actor := _actor()
	var state := actor.path(MindPath.PATH_ID)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var succeeded := false
	for _attempt in 30:
		if _prepare(actor) == null:
			break
		if MindAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough eventually succeeded")
	assert_ne(state.rank_id, &"qi_refining", "realm advanced")


func test_breakthrough_consumes_the_pill() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var succeeded := false
	var pill: StringName = &""
	for _attempt in 30:
		var seed := _prepare(actor)
		if seed == null:
			break
		pill = seed.breakthrough_item
		if MindAdvancement.try_breakthrough(actor, rng):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough succeeded")
	assert_eq(ItemsApi.has_item(actor, pill), false, "pill consumed")


func test_deviation_turbulates_the_sea_and_damages_a_channel() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "seed loaded")
	var state := actor.path(MindPath.PATH_ID)
	var start_rank := state.rank_id
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	# Rolls are not forced, so keep re-preparing until one deviates. A success
	# only moves the target realm; it does not invalidate the search.
	var deviated := false
	var attempts := 0
	while attempts < 40 and not deviated:
		attempts += 1
		var current := _prepare(actor)
		if current == null:
			break
		if MindAdvancement.try_breakthrough(actor, rng):
			# A success advances the realm, so the next _prepare would target a
			# different realm and the search would eventually run off the top of
			# the ladder without ever rolling a deviation. Rewind and keep testing
			# the same realm until a deviation lands.
			actor.set_path(PathState.new(MindPath.PATH_ID, start_rank))
			continue
		var sea := MindCultivationApi.sea(actor)
		var channel_damaged := false
		for meridian_id in current.required_meridians:
			if actor.meridians.get_meridian(meridian_id).is_injured():
				channel_damaged = true
		deviated = sea.turbulence > 0.0 and channel_damaged
	assert_eq(deviated, true, "deviation clouded the sea and burned a channel")
