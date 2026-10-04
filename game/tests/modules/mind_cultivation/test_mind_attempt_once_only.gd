extends TestCase

## ADR 0029's once-only award guarantee, isolated and proved to be keyed on the
## attempt record's OWN flag rather than on any incidental fact about the path's
## state. `test_breakthrough_attempt.gd` covers the lifecycle; this suite exists
## because the shortcut is invisible there.
##
## Advancing zeroes the path's progress, so "progress is zero" looks like a
## reasonable proxy for "this attempt was granted". It is not. Every test here is
## built so that at least one such proxy gives the wrong answer, and only the
## record's `outcome_granted` flag gives the right one.
##
## Fixtures mirror `test_breakthrough_attempt.gd`: bring an actor to the brink of
## the next realm through public actions, then commit an attempt. No drain, no
## hand-written progress — see that suite for why the fixture must not do the
## player's job.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


func _actor() -> Actor:
	var actor := Actor.new(
		&"once_only_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	return actor


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
	assert_eq(
		Probe.train_channels(actor, source_seed), true, "channels trained in %s" % state.rank_id
	)
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.calm_sea(actor), true, "sea calm in %s" % state.rank_id)
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened in %s" % state.rank_id)
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned for %s" % target.id)
	assert_eq(Probe.fill_sea(actor), true, "sea filled for %s" % target.id)
	return target_seed


## Top the actor up on a real authored item until it holds one. `train_channel` and
## `start` each consume one, and a preparing loop takes several.
func _stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := Crafting.resolve(def_id)
	if def == null:
		return
	var guard := 0
	while not ItemsApi.has_item(actor, def_id) and guard < 64:
		ItemsApi.inventory(actor).add(def, 1)
		guard += 1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A seed whose first draw wins `actor`'s published chance, so a case that NEEDS a
## success can have one deterministically. Arithmetic over `MindAttemptRoll.replay`,
## which is the generator the resolve itself builds, so this asks exactly the
## question the module answers. Bounded and RETURNING.
func _winning(actor: Actor) -> RandomNumberGenerator:
	var chance := float(MindAdvancement.preview(actor).get("chance", 0.0))
	for candidate in range(MindAttemptRoll.MIN_SEED, 256):
		if MindAttemptRoll.replay(candidate).randf() < chance:
			return _rng(candidate)
	return _rng(0)


## The strongest form of the rule, and the case that separates it from every
## incidental shortcut a future agent might reach for.
##
## An attempt whose target realm is where the actor ALREADY stands — because
## something else advanced this path while the attempt was in flight — must be
## cancelled, not treated as already granted. `resolve_attempt` returns `false`
## and reports `STATUS_CANCELLED`.
##
## The distinction is not academic. Every plausible shortcut is contradicted by a
## different half of this test:
##   - keyed on path PROGRESS, which `try_advance` zeroes on success: progress is
##     still at its pre-attempt value here, so such a guard would not fire at all;
##   - keyed on the rank EQUALING the target: it matches immediately, so the guard
##     fires and the attempt looks granted — but nothing was granted, so the pill
##     `start` already spent is unaccounted for and the record lies;
##   - keyed on the status alone: `committed` is active, so nothing fires.
##
## Only the attempt's OWN `outcome_granted` flag answers this correctly: it is
## false, so the attempt is stale, and `resolve_attempt` takes the stale branch.
func test_an_attempt_already_at_its_target_is_cancelled_not_treated_as_granted() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	var started := MindAdvancement.start(actor, _rng(8))
	assert_ne(started, null, "attempt started")
	assert_eq(started.target_rank, seed.id, "the attempt names the realm it was fighting for")
	assert_eq(started.outcome_granted, false, "nothing granted yet")

	# The path arrives at the attempt's target by some other route while the
	# attempt is still committed. Progress is untouched: only the rank moved.
	actor.path(MindPath.PATH_ID).rank_id = started.target_rank
	var stale := MindAdvancement.attempt(actor)
	assert_eq(stale.is_active(), true, "still an active attempt")
	assert_eq(stale.outcome_granted, false, "still not granted")

	assert_eq(MindAdvancement.resolve_attempt(actor), false, "no award")
	assert_eq(actor.stats.get_base(Stat.WILL), will, "the award was NOT granted a second time")
	assert_eq(
		MindAdvancement.attempt(actor).status,
		MindAttempt.STATUS_CANCELLED,
		"cancelled rather than marked granted: no trial ran"
	)
	assert_eq(
		MindAdvancement.attempt(actor).outcome_granted,
		false,
		"the record does not claim an outcome it never had"
	)
	assert_eq(
		Breakthrough.can_advance(actor, MindPath.PATH_ID, MindBreakthroughCondition.new()),
		false,
		"and the gate into the realm after it is genuinely closed, not open on a lie"
	)


## The mirror of the test above, and the only way to observe the guard firing on
## the flag ALONE: a record whose flag is set while the actor still stands in the
## SOURCE realm. `resolve_attempt` must short-circuit and report the same answer,
## granting nothing and advancing nothing.
##
## A guard keyed on progress cannot pass this: progress is at the target's
## requirement, not zero. A guard keyed on the rank cannot either: the rank is
## still the source. Only the flag is true here, so only the flag can produce
## this outcome.
func test_a_flagged_attempt_short_circuits_before_any_work() -> void:
	var actor := _actor()
	_prepare(actor)
	var started := MindAdvancement.start(actor, _rng(12))
	assert_ne(started, null, "attempt started")
	var will := actor.stats.get_base(Stat.WILL)
	var progress := actor.path(MindPath.PATH_ID).progress
	assert_eq(progress > 0.0, true, "progress is not zero: a progress proxy cannot pass this")

	started.outcome_granted = true
	actor.set_module_data(MindAdvancement.ATTEMPT_KEY, started.to_dict())
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "granted, as flagged")
	assert_eq(actor.stats.get_base(Stat.WILL), will, "nothing actually granted")
	assert_eq(
		actor.path(MindPath.PATH_ID).rank_id,
		&"qi_refining",
		"and no advance either: the flag short-circuits before any of the work"
	)
	assert_almost_eq(actor.path(MindPath.PATH_ID).progress, progress, "progress untouched", 0.0001)


## The flag survives the round trip, which is what makes the guarantee hold across
## a save. A payload that lost `outcome_granted` would let a reload grant the same
## award twice.
func test_the_once_only_flag_survives_save_and_load() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var will := actor.stats.get_base(Stat.WILL)
	# A SEARCHED winning seed, not a typed-in one. With the resolve reading the
	# record, a hard-coded `17` would make this case a coin flip: the commit would
	# store 17 and the outcome would be whatever 17 draws. The seed is chosen to
	# beat the published chance so the property under test — the flag, not the roll
	# — is the only thing that can decide it.
	var rng := _winning(actor)
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), true, "resolved as a success")
	var after_first := actor.stats.get_base(Stat.WILL)
	assert_eq(after_first > will, true, "the award landed")

	var restored := Actor.from_dict(actor.to_dict())
	var reloaded := MindAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "the record came back")
	assert_eq(reloaded.outcome_granted, true, "the once-only flag came back with it")
	assert_eq(MindAdvancement.resolve_attempt(restored), true, "same answer after the reload")
	assert_eq(restored.stats.get_base(Stat.WILL), after_first, "and still no second award")
	assert_eq(restored.path(MindPath.PATH_ID).rank_id, seed.id, "still exactly one realm on")
