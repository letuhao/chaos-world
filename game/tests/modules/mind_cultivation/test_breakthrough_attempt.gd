extends TestCase

## ADR 0029: a Mind breakthrough is transactional. `preview` consumes nothing,
## `start` commits a persisted attempt that spends the realm pill exactly once,
## `resolve_attempt` grants the realm's awards exactly once or applies a
## recoverable deviation, and the record survives save/load.
##
## Tests own the RNG: a roll is searched for deterministically, never hoped for.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## How far a seed search looks. Bounded and RETURNING: neither search below appends
## to anything, so this cannot be outgrown.
const SEED_BOUND := 256


func _actor() -> Actor:
	var actor := Actor.new(
		&"attempt_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


## Bring the actor to the brink of the next realm through public actions. Entry
## checks the source realm's milestones (ADR 0029), so the sea and the channels
## go to the *current* realm's targets.
##
## No drain and no hand-written progress. The transactional guarantees below are
## only worth anything if the state they operate on is one a player can produce,
## and this fixture used to produce it by emptying the sea itself.
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
	_stock(actor, source_seed.recovery_item)
	assert_eq(
		Probe.train_channels(actor, source_seed), true, "channels trained in %s" % state.rank_id
	)
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.calm_sea(actor), true, "sea calm in %s" % state.rank_id)
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened in %s" % state.rank_id)
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned for %s" % target.id)
	assert_eq(Probe.fill_sea(actor), true, "sea filled for %s" % target.id)
	return target_seed


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A seed whose first draw wins the evaluated chance.
##
## PURE ARITHMETIC over the module's own `MindAttemptRoll.replay`, which is exactly
## what `resolve_attempt` builds its generator from. It used to drive the whole
## prepare-and-resolve pipeline once per candidate, making this search the single
## largest source of assertions in the suite, and it searched for something weaker
## than it claimed: the resolve it drove was handed the generator rather than the
## record. Probing the helper directly asks the same question exactly.
##
## Bounded by `SEED_BOUND` and RETURNING, so neither search can be the loop that
## fails to terminate.
func _winning_seed(chance: float) -> int:
	for candidate in range(MindAttemptRoll.MIN_SEED, SEED_BOUND):
		if MindAttemptRoll.replay(candidate).randf() < chance:
			return candidate
	return 0


## And the first seed that loses it, so the refusing resolve path is reached
## deterministically instead of by a roll that happens to fail.
func _losing_seed(chance: float) -> int:
	for candidate in range(MindAttemptRoll.MIN_SEED, SEED_BOUND):
		if MindAttemptRoll.replay(candidate).randf() >= chance:
			return candidate
	return 0


## The chance a prepared actor commits against, paired with a seed that beats it.
## Every determinate case here goes through one of these two, so the search and the
## commit can never be asked about different numbers.
func _winning(actor: Actor) -> RandomNumberGenerator:
	var chance := float(MindAdvancement.preview(actor).get("chance", 0.0))
	var found := _winning_seed(chance)
	assert_ne(found, 0, "a winning seed exists for chance %.4f" % chance)
	return _rng(found)


## And the seed that loses, against that same published chance.
func _losing(actor: Actor) -> RandomNumberGenerator:
	var chance := float(MindAdvancement.preview(actor).get("chance", 0.0))
	var found := _losing_seed(chance)
	assert_ne(found, 0, "a losing seed exists for chance %.4f" % chance)
	return _rng(found)


func _injured_channel(actor: Actor, seed: MindRealmSeed) -> StringName:
	for meridian_id in seed.required_meridians:
		if actor.meridians.get_meridian(meridian_id).is_injured():
			return meridian_id
	return &""


## Total the target realm awards to a single base stat, summed across the
## authored reward keys.
func _award(seed: MindRealmSeed) -> float:
	var total := 0.0
	for key in seed.rewards:
		total += float(seed.rewards[key])
	return total


# --- Preview ----------------------------------------------------------------


func test_preview_consumes_nothing() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var rank := actor.path(MindPath.PATH_ID).rank_id
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	var stored := actor.stats.get_base(Stat.WILL)
	var preview := MindAdvancement.preview(actor)
	assert_eq(preview.get("ready"), true, "prepared means ready")
	assert_eq(preview.get("target"), seed.id, "preview targets the next realm")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), pills, "pill untouched")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, rank, "rank unchanged")
	assert_eq(actor.stats.get_base(Stat.WILL), stored, "no award granted")
	assert_eq(MindAdvancement.attempt(actor) == null, true, "no attempt created")
	assert_eq(preview.get("attempt"), "", "no attempt reported")


func test_preview_reports_an_attempt_in_flight() -> void:
	var actor := _actor()
	_prepare(actor)
	var started := MindAdvancement.start(actor, _rng(7))
	assert_ne(started, null, "attempt started")
	assert_eq(MindAdvancement.preview(actor).get("attempt"), String(started.attempt_id), "reported")


func test_preview_is_side_effect_free_before_preparation() -> void:
	var actor := _actor()
	var preview := MindAdvancement.preview(actor)
	assert_eq(preview.get("ready"), false, "unprepared, not ready")
	assert_ne(preview.get("conditions"), [], "conditions reported")
	assert_eq(MindAdvancement.attempt(actor) == null, true, "still no attempt")


# --- Start ------------------------------------------------------------------


func test_start_is_refused_before_preparation() -> void:
	assert_eq(MindAdvancement.start(_actor(), _rng(1)) == null, true, "nothing to attempt")


func test_start_persists_an_attempt_id_and_spends_one_pill() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	var started := MindAdvancement.start(actor, _rng(11))
	assert_ne(started, null, "attempt started")
	assert_ne(started.attempt_id, &"", "attempt has an id")
	assert_eq(started.source_rank, &"qi_refining", "source realm recorded")
	assert_eq(started.target_rank, seed.id, "target realm recorded")
	assert_eq(started.path_id, MindPath.PATH_ID, "path recorded")
	assert_eq(started.status, MindAttempt.STATUS_COMMITTED, "committed, not resolved")
	assert_eq(started.pill_consumed, true, "pill consumed once")
	assert_eq(started.trial_complete, false, "trial not run yet")
	assert_eq(started.outcome_granted, false, "no outcome granted yet")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), pills - 1, "one pill spent")
	# The record is persisted on the actor, so it survives a save.
	var stored := MindAdvancement.attempt(actor)
	assert_ne(stored == null, true, "record stored")
	assert_eq(stored.attempt_id, started.attempt_id, "stored id matches")
	assert_eq(stored.is_active(), true, "still active after start")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "no advance yet")


func test_a_second_start_while_active_is_refused() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(MindAdvancement.start(actor, _rng(3)), null, "first attempt started")
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	assert_eq(MindAdvancement.start(actor, _rng(4)) == null, true, "second start refused")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), pills, "no extra pill spent")


func test_start_chances_a_fixed_preparation_and_rolls_nothing() -> void:
	var actor := _actor()
	_prepare(actor)
	var rng := _rng(9)
	var before := rng.state
	var started := MindAdvancement.start(actor, rng)
	assert_eq(rng.state, before, "start consumes no randomness")
	assert_eq(
		started.preparation.get("chance"),
		MindAdvancement.preview(actor).get("chance"),
		"same chance"
	)
	assert_eq(float(started.preparation.get("progress")) > 0.0, true, "progress snapshotted")
	assert_eq(rng.seed, 9, "seed recorded for replay")
	assert_eq(started.rng_state, 9, "attempt keeps the seed it committed to")


# --- Resolve ----------------------------------------------------------------


func test_resolve_without_an_attempt_is_a_noop() -> void:
	assert_eq(MindAdvancement.resolve_attempt(_actor()), false, "nothing to resolve")


func test_resolve_success_grants_the_award_once() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	var rng := _winning(actor)
	var started := MindAdvancement.start(actor, rng)
	assert_ne(started, null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "resolved as a success")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, seed.id, "advanced exactly one realm")
	assert_eq(actor.stats.get_base(Stat.WILL), will + _award(seed), "award granted")
	var resolved := MindAdvancement.attempt(actor)
	assert_eq(resolved.status, MindAttempt.STATUS_SUCCESS, "record is successful")
	assert_eq(resolved.outcome_granted, true, "outcome flagged")
	assert_eq(resolved.trial_complete, true, "trial ran")
	assert_eq(resolved.is_active(), false, "no longer active")


func test_resolving_twice_does_not_grant_twice() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	var rng := _winning(actor)
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "first resolve grants")
	var after_first := actor.stats.get_base(Stat.WILL)
	assert_eq(after_first, will + _award(seed), "award granted once")
	# The award is keyed on the attempt's identity, so a second resolve of the
	# same record cannot grant again even though the path already moved.
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "already granted, same answer")
	assert_eq(actor.stats.get_base(Stat.WILL), after_first, "no second award")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, seed.id, "no second advance")
	assert_eq(actor.path(MindPath.PATH_ID).progress, 0.0, "progress untouched by the replay")


func test_failure_keeps_the_realm_and_is_recoverable() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var rng := _losing(actor)
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "the trial deviated")
	var sea := MindCultivationApi.sea(actor)
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "realm kept")
	assert_eq(sea.turbulence > 0.0, true, "the sea clouded")
	var burned := _injured_channel(actor, seed)
	assert_ne(burned, &"", "a channel burned")
	var deviated := MindAdvancement.attempt(actor)
	assert_eq(deviated.status, MindAttempt.STATUS_FAILED, "record is failed")
	assert_eq(deviated.outcome_granted, false, "no outcome granted")
	assert_eq(deviated.trial_complete, true, "the trial did run")
	assert_eq(MindAdvancement.active_attempt(actor) == null, true, "slot is free again")
	# Recovery is the mind system's own, at the same realm.
	assert_eq(MindTraining.recover(actor, burned), true, "recovery spent the realm elixir")
	assert_eq(sea.turbulence, 0.0, "turbulence cleared")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "channel repaired")
	assert_ne(_prepare(actor), null, "prepared again after the deviation")
	var retry := _winning(actor)
	assert_ne(MindAdvancement.start(actor, retry), null, "retry started")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "retry succeeds")


func test_resolving_a_failed_attempt_again_owes_no_second_deviation() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var rng := _losing(actor)
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "deviated")
	var turbulence := MindCultivationApi.sea(actor).turbulence
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "still no award")
	assert_eq(MindCultivationApi.sea(actor).turbulence, turbulence, "no second deviation")
	assert_eq(_injured_channel(actor, seed) != &"", true, "the first burn stands")


func test_cancel_keeps_the_realm_and_owes_no_deviation() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var sea := MindCultivationApi.sea(actor)
	var stored := sea.structural_capacity
	assert_ne(MindAdvancement.start(actor, _rng(2)), null, "attempt started")
	assert_eq(MindAdvancement.cancel(actor), true, "attempt cancelled")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "realm kept")
	assert_eq(sea.turbulence, 0.0, "no deviation cloud")
	assert_eq(sea.structural_capacity, stored, "sea undamaged")
	assert_eq(_injured_channel(actor, seed), &"", "no channel burned")
	var cancelled := MindAdvancement.attempt(actor)
	assert_eq(cancelled.status, MindAttempt.STATUS_CANCELLED, "record is cancelled")
	assert_eq(cancelled.trial_complete, false, "no trial ran")
	assert_eq(cancelled.outcome_granted, false, "no outcome granted")
	assert_eq(MindAdvancement.cancel(actor), false, "nothing left to cancel")
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "a cancelled attempt never resolves")
	assert_eq(MindAdvancement.active_attempt(actor) == null, true, "the next attempt may start")
	# The pill stayed spent, so recovery costs a fresh one.
	assert_ne(_prepare(actor), null, "prepared again")
	assert_ne(MindAdvancement.start(actor, _rng(2)), null, "retry after cancelling")


func test_a_stale_attempt_is_cancelled_without_firing() -> void:
	var actor := _actor()
	_prepare(actor)
	var started := MindAdvancement.start(actor, _rng(6))
	assert_ne(started, null, "attempt started")
	# Something else moved this actor on, so the committed trial cannot fire.
	actor.path(MindPath.PATH_ID).rank_id = &"core_formation"
	var will := actor.stats.get_base(Stat.WILL)
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "stale attempt did not fire")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"core_formation", "rank untouched")
	assert_eq(actor.stats.get_base(Stat.WILL), will, "no award granted")
	assert_eq(MindAdvancement.attempt(actor).status, MindAttempt.STATUS_CANCELLED, "cancelled")


## The once-only award guarantee is proved against every incidental shortcut in
## `test_mind_attempt_once_only.gd`; a pointer here so the pair is not mistaken
## for duplicate coverage.
func test_the_once_only_guard_lives_in_its_own_suite() -> void:
	var actor := _actor()
	_prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	var rng := _winning(actor)
	var started := MindAdvancement.start(actor, rng)
	assert_ne(started, null, "attempt started")
	assert_eq(started.outcome_granted, false, "the record, not the path, carries the guard")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "granted once")
	assert_eq(actor.stats.get_base(Stat.WILL) > will, true, "the award landed on the actor")


func test_try_breakthrough_is_the_one_shot_wrapper() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	var rng := _winning(actor)
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), true, "one shot succeeded")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, seed.id, "advanced")
	assert_eq(actor.stats.get_base(Stat.WILL), will + _award(seed), "granted once")
	# Same record, same guard: the wrapper cannot be replayed for a second award.
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), false, "no second attempt to run")


# --- Persistence ------------------------------------------------------------


## The saved attempt resolves from ITS OWN seed, which is the whole point of storing
## one.
##
## It used to commit with seed 21 and then resolve with a hand-searched WINNING seed,
## asserting a victory the record never licensed — so the `rng_state` it round-tripped
## above was decorative, and this case was green through a resolve that ignored it.
## That is the shape that hid the defect: a test that names the field in an assertion
## and then does not use it.
##
## So the outcome asserted here is the one seed 21 actually produces, read off the
## record, and the twin actor committed with the SAME seed is resolved alongside it.
## If the resolve ever takes a generator again, or draws from the commit's stream
## rather than the stored seed, the two answers part and this goes red.
func test_a_pending_attempt_survives_save_and_load() -> void:
	var actor := _actor()
	_prepare(actor)
	var started := MindAdvancement.start(actor, _rng(21))
	assert_ne(started, null, "attempt started")
	var stored_chance := float(started.preparation.get("chance", 0.0))
	var stored_seed := started.rng_state
	assert_eq(stored_seed, 21, "the record names the seed it was given")
	# The twin is the answer this attempt WOULD have had with no save in between.
	var twin := _actor()
	_prepare(twin)
	assert_ne(MindAdvancement.start(twin, _rng(21)), null, "the twin committed the same seed")
	var without_reload := MindAdvancement.resolve_attempt(twin)
	var expected := MindAttemptRoll.replay(stored_seed).randf() < stored_chance
	assert_eq(without_reload, expected, "seed 21 alone decides the verdict")
	var restored := Actor.from_dict(actor.to_dict())
	var reloaded := MindAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "attempt restored")
	assert_eq(reloaded.attempt_id, started.attempt_id, "id survived")
	assert_eq(reloaded.status, started.status, "status survived")
	assert_eq(reloaded.target_rank, started.target_rank, "target survived")
	assert_eq(reloaded.source_rank, started.source_rank, "source survived")
	assert_eq(reloaded.pill_consumed, true, "the spent pill is still recorded")
	assert_eq(
		reloaded.preparation.get("chance"), started.preparation.get("chance"), "chance survived"
	)
	assert_eq(reloaded.rng_state, stored_seed, "and the SEED survived, which is the roll")
	assert_eq(MindAdvancement.active_attempt(restored) == null, false, "still active after load")
	# Re-attach as the composition root would, then resolve the loaded attempt.
	MindCultivationApi.attach(restored)
	MindCultivationApi.attach_sea(restored)
	ItemsApi.attach(restored)
	MindTraining.synchronize(restored)
	var after_reload := MindAdvancement.resolve_attempt(restored)
	assert_eq(after_reload, without_reload, "a reload did not re-roll the attempt")
	assert_eq(
		after_reload,
		expected,
		"and the reloaded verdict is the one the stored roll names, not a fresh one"
	)
	assert_eq(
		String(restored.path(MindPath.PATH_ID).rank_id) == started.target_rank,
		after_reload,
		"the realm the restored actor stands in is the verdict"
	)


func test_a_terminal_attempt_survives_save_and_load() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var rng := _winning(actor)
	var started := MindAdvancement.start(actor, rng)
	assert_ne(started, null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "resolved")
	var restored := Actor.from_dict(actor.to_dict())
	var reloaded := MindAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "resolved record restored")
	assert_eq(reloaded.attempt_id, started.attempt_id, "id survived")
	assert_eq(reloaded.status, MindAttempt.STATUS_SUCCESS, "still successful")
	assert_eq(reloaded.outcome_granted, true, "outcome flag survived")
	# The flag is what stops a reload from granting the same award twice.
	assert_eq(MindAdvancement.resolve_attempt(restored), true, "same answer")
	assert_eq(restored.path(MindPath.PATH_ID).rank_id, seed.id, "no second advance")
