extends TestCase

## ADR 0024: the mind-cultivation action layer — filling the sea, meditating to
## calm turbulence, training a channel, and the seeded breakthrough.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


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
## Prepare the actor to attempt the next realm. Entry checks the *source*
## realm's milestones (ADR 0029), so the sea and channels are brought to the
## source realm's targets, not the target realm's.
##
## No drain and no hand-written progress: the actor has to be able to reach this
## state the way a player reaches it, or these tests measure the fixture.
func _prepare(actor: Actor) -> MindRealmSeed:
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, target_seed.breakthrough_item)
	_stock(actor, source_seed.training_item)
	_stock(actor, source_seed.sea_catalyst)
	# A deviation damages a channel, and a damaged channel satisfies nothing, so
	# the repair is a step of its own before the climb.
	assert_eq(
		Probe.train_channels(actor, source_seed), true, "channels trained in %s" % state.rank_id
	)
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.calm_sea(actor), true, "sea calm in %s" % state.rank_id)
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened in %s" % state.rank_id)
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned for %s" % target.id)
	assert_eq(Probe.fill_sea(actor), true, "sea filled for %s" % target.id)
	return target_seed


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
	# No drain: the reservoir starts empty, which is the state a fresh actor is
	# in, and draining it here would only be hiding a full-sea refusal.
	assert_eq(MindTraining.cultivate(actor, 50.0), true, "cultivation applied")
	assert_eq(sea.current(actor) > 0.0, true, "mind power stored")
	assert_eq(actor.path(MindPath.PATH_ID).progress > 0.0, true, "progress grew")


func test_cultivate_sharpens_clarity() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_clarity(0.0)
	MindTraining.cultivate(actor, 500.0)
	assert_eq(sea.clarity > 0.0, true, "clarity sharpened")


## The reservoir is the FIRST gate a real actor meets and the progress floor is
## the second, so a full sea must stop *storing* and not *training*. This test
## used to assert the opposite — that `cultivate` refuses a full sea — and that
## assertion is what hid the deadlock: refusing made the progress floor
## unreachable, the suite answered by draining the sea itself, and a failed
## breakthrough (which halves progress without draining) became permanent.
func test_a_full_sea_still_earns_progress_and_insight() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.fill(actor, sea.effective_capacity())
	assert_eq(sea.is_full(actor), true, "the sea really is full first")
	var progress_before := actor.path(MindPath.PATH_ID).progress
	var comprehension_before := actor.stats.get_base(Stat.COMPREHENSION)
	assert_eq(MindTraining.cultivate(actor, 10.0), true, "a full sea still trains")
	assert_eq(actor.path(MindPath.PATH_ID).progress > progress_before, true, "progress still grows")
	assert_eq(
		actor.stats.get_base(Stat.COMPREHENSION) > comprehension_before, true, "insight still grows"
	)
	assert_eq(sea.current(actor), sea.maximum(actor), "the surplus is simply not stored")


func test_cultivate_refuses_nothing_that_a_player_could_do() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.fill(actor, sea.effective_capacity())
	sea.add_turbulence(0.5)
	sea.set_clarity(0.0)
	# Clouded, blurred and full: the exact state a deviation leaves behind. Every
	# one of those used to make `cultivate` the only remaining action, and it is
	# the action that has to keep working or the realm is never earned again.
	assert_eq(MindTraining.cultivate(actor, 500.0), true, "cultivate works on a clouded full sea")
	assert_eq(
		actor.path(MindPath.PATH_ID).progress > 0.0,
		true,
		"progress is still earnable after a deviation"
	)


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


## A burn is REPAIRED, not trained, and the repair is priced by the realm's
## `recovery_item` rather than by the channel elixir (ADR 0031): `train_channel`
## hands a burn to `recover`, so there is one repair at one price.
##
## The old version of this test stocked `training_item` and called the repair a
## training step, which is exactly why the wrong consumable went unnoticed — the
## price of a repair was checked by nothing in the suite, so the repair the player
## could afford and the repair the seed authors are two different acts. Counts are
## read from the inventory rather than assumed, so "spent the wrong one" is a
## failure and not an unmeasured detail.
func test_train_channel_repairs_a_burn_at_the_recovery_elixir_price() -> void:
	var actor := _actor()
	var seed := MindRealmSeed.for_realm(&"qi_refining")
	assert_ne(seed.recovery_item, &"", "the realm authors a recovery elixir (ADR 0031)")
	assert_ne(
		seed.recovery_item, seed.training_item, "and it is a different consumable from the elixir"
	)
	actor.meridians.damage_meridian(&"lung")
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	var elixirs := ItemsApi.inventory(actor).count(seed.training_item)
	var recoveries := ItemsApi.inventory(actor).count(seed.recovery_item)
	assert_eq(MindTraining.train_channel(actor, &"lung"), true, "repaired")
	assert_eq(actor.meridians.get_meridian(&"lung").is_injured(), false, "no longer injured")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.recovery_item),
		recoveries - 1,
		"the realm's recovery elixir paid for it"
	)
	assert_eq(
		ItemsApi.inventory(actor).count(seed.training_item),
		elixirs,
		"and the channel elixir did not: a repair is not one training step"
	)


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


## One generator PER PRESS, never one generator looped.
##
## This is the trap `MindAttemptRoll` exists to document, and these three cases are
## where it bites. A caller's `rng` is a SEED SOURCE: the commit stores `rng.seed`
## and the resolve replays that stored seed from a fresh generator. So thirty
## attempts handed the SAME generator store the SAME seed thirty times and replay one
## roll thirty times — the searches below could never reach the other outcome, and
## they only ever passed because the shipped path was drawing seed 0, which won every
## realm. Re-seeding per press is what makes the loop a search again.
func _press_rng(press: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = press + 1
	return rng


func test_breakthrough_succeeds_and_advances() -> void:
	var actor := _actor()
	var state := actor.path(MindPath.PATH_ID)
	var succeeded := false
	for press in 30:
		if _prepare(actor) == null:
			break
		if MindAdvancement.try_breakthrough(actor, _press_rng(press)):
			succeeded = true
			break
	assert_eq(succeeded, true, "breakthrough eventually succeeded")
	assert_ne(state.rank_id, &"qi_refining", "realm advanced")


func test_breakthrough_consumes_the_pill() -> void:
	var actor := _actor()
	var succeeded := false
	var pill: StringName = &""
	for press in 30:
		var seed := _prepare(actor)
		if seed == null:
			break
		pill = seed.breakthrough_item
		if MindAdvancement.try_breakthrough(actor, _press_rng(press)):
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
	# Rolls are not forced, so keep re-preparing until one deviates. A success
	# only moves the target realm; it does not invalidate the search. Bounded by
	# the `for`, and the assertion below names what was never found. Each press
	# carries its OWN seed — see `_press_rng`.
	var deviated := false
	for press in 40:
		var current := _prepare(actor)
		if current == null:
			break
		if MindAdvancement.try_breakthrough(actor, _press_rng(press)):
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
		if sea.turbulence > 0.0 and channel_damaged:
			deviated = true
			break
	assert_eq(deviated, true, "deviation clouded the sea and burned a channel")
