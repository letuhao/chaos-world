extends TestCase

## ADR 0024/0095: the qi-cultivation action layer — refining the dantian, training a
## meridian, and the seeded breakthrough that spends the pill.
##
## Every preparation below goes through the production actions and through authored
## content. It used to mint `ItemDef` stubs and to call `open_meridian` /
## `expand_meridian` / `strengthen_meridian` directly, which asserted the gate
## against a state the fixture had written itself: a gate no player could satisfy
## still measured as satisfied. `test_qi_channel_ladder.gd` now owns the
## reachability proof; this suite owns the mechanism.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID


func _actor() -> Actor:
	var actor := Actor.new(&"qi_hero", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0})
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	# A roomy inventory: repeated attempts re-stock both items each roll.
	ItemsApi.attach(actor, 400)
	QiTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	assert_eq(Probe.stock(actor, def_id, 1), true, "authored item %s stocked" % def_id)


## Bring the actor to the brink of the next realm through public actions only.
func _prepare(actor: Actor) -> QiRealmSeed:
	var state := actor.path(PATH)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	# A deviation injures a channel, and an injured channel refuses to climb, so
	# close every wound before training or the next attempt can never qualify.
	Probe.recover_all(actor)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, seed.training_item)
	assert_eq(Probe.train_gate_channels(actor, seed), true, "channels trained for %s" % target.id)
	Probe.recover_all(actor)
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(seed.dantian_capacity)
	dantian.set_quality(seed.dantian_quality_required)
	QiTraining.synchronize(actor)
	dantian.drain(actor, dantian.current(actor))
	dantian.fill(actor, dantian.effective_capacity())
	# The work budget is earned, not written: `cultivate` is the only thing that
	# moves it, and a fixture that assigns it proves the gate against itself.
	assert_eq(Probe.earn_progress(actor, seed), true, "progress earned for %s" % target.id)
	return seed


# --- Synchronize -----------------------------------------------------------


func test_synchronize_sets_capacity_tier_and_unlocks() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	assert_eq(dantian != null, true, "dantian attached")
	assert_eq(dantian.tier, &"lower", "Mortal uses the lower dantian")
	assert_almost_eq(dantian.structural_capacity, 100.0, "capacity from the seed")


func test_synchronize_scales_capacity_with_meridian_bonus() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	var base := dantian.structural_capacity
	QiTraining.synchronize(actor)
	assert_eq(dantian.structural_capacity > base, true, "expanded channels widen the dantian")


func test_synchronize_clamps_stored_qi() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.fill(actor, dantian.effective_capacity())
	QiTraining.synchronize(actor)
	assert_almost_eq(
		dantian.current(actor), dantian.effective_capacity(), "full dantian stays full"
	)


# --- Cultivation -----------------------------------------------------------


func test_cultivate_fills_the_dantian_and_advances_progress() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.drain(actor, dantian.current(actor))
	assert_eq(QiTraining.cultivate(actor, 50.0), true, "cultivation applied")
	assert_eq(dantian.current(actor) > 0.0, true, "qi stored")
	assert_eq(actor.path(QiPath.PATH_ID).progress > 0.0, true, "progress grew")


func test_cultivate_refines_dantian_quality() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.drain(actor, dantian.current(actor))
	dantian.set_quality(0.0)
	QiTraining.cultivate(actor, 500.0)
	assert_eq(dantian.quality > 0.0, true, "quality refined by circulation")


func test_every_realm_quality_gate_is_reachable_by_circulating_qi() -> void:
	# ADR 0028's reachable-gates rule. Quality is refined toward the *next*
	# realm's floor, so one realm of training must be able to reach it. This
	# failed for 28 of 29 transitions when the ceiling was the current realm's own
	# requirement, because every realm's floor rises above the one before it.
	for previous in RealmDefaults.ladder().realms():
		var next := RealmDefaults.ladder().next(previous.id)
		if next == null:
			continue
		var to_seed := QiRealmSeed.for_realm(next.id)
		if to_seed == null:
			continue
		var actor := Actor.new(&"qi_ceiling", {QiStats.DANTIAN_CAPACITY: 100.0})
		actor.set_path(PathState.new(QiPath.PATH_ID, previous.id))
		actor.meridians.unlock_for_realm(previous.id)
		QiCultivationApi.attach(actor)
		var dantian := QiAccess.dantian(actor)
		dantian.set_quality(0.0)
		QiTraining.synchronize(actor)
		var guard := 0
		while guard < 4096 and dantian.quality < to_seed.dantian_quality_required:
			guard += 1
			QiTraining.cultivate(actor, 25.0)
		assert_eq(
			dantian.quality >= to_seed.dantian_quality_required,
			true,
			"quality floor for %s reachable from %s" % [next.id, previous.id]
		)


func test_cultivate_keeps_training_when_the_dantian_is_full() -> void:
	# A full dantian stops *storing* qi, not training. Refusing the whole action
	# deadlocked the path: the entry gate wants a full reservoir AND a met
	# progress floor, and the reservoir fills first, so progress could never
	# catch up.
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.fill(actor, dantian.effective_capacity())
	var full := dantian.current(actor)
	var progress_before := actor.path(QiPath.PATH_ID).progress
	assert_eq(QiTraining.cultivate(actor, 10.0), true, "training continues")
	assert_eq(dantian.current(actor), full, "no qi stored beyond capacity")
	assert_eq(
		actor.path(QiPath.PATH_ID).progress > progress_before, true, "progress still advances"
	)


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


## The recovery elixir is stocked, not the channel elixir: `train_channel` hands a
## burn to `recover` (`training.gd:155-156`), which is priced by `recovery_item`
## (ADR 0141). This test stocked `training_item` and so asserted that the channel
## elixir alone repairs a burn — the exact defect ADR 0141 recorded and deleted,
## still asserted here. `test_qi_repair_pricing.gd:110-120` asserts the opposite of
## what this said, so the two suites contradicted each other and only the pricing
## suite was right.
func test_train_channel_repairs_an_injured_channel() -> void:
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, seed.recovery_item)
	assert_eq(QiTraining.train_channel(actor, &"lung"), true, "repaired")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "no longer injured")


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
		var dantian := QiAccess.dantian(actor)
		var channel_injured := false
		for meridian_id in current.required_meridians:
			if actor.meridians.get_meridian(meridian_id).is_injured():
				channel_injured = true
		deviated = dantian.injured and channel_injured
	assert_eq(deviated, true, "deviation scarred the dantian and burned a channel")


func test_damaged_dantian_reduces_usable_capacity() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	var full := dantian.effective_capacity()
	dantian.damage()
	assert_almost_eq(dantian.effective_capacity(), full * 0.75, "damage costs 25% capacity")
	dantian.heal()
	assert_almost_eq(dantian.effective_capacity(), full, "healing restores capacity")
