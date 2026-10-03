extends TestCase

## The once-only award guarantee, isolated and proved to be keyed on the attempt
## record's OWN flag rather than on any incidental fact about the actor.
## `test_breakthrough_attempt.gd` covers the lifecycle; this suite exists because
## the shortcut is invisible there.
##
## The award is `stats.set_base(id, get_base(id) + reward)` — a cumulative write
## keyed on nothing at all. Advancing zeroes the path's progress, so "progress is
## zero" looks like a reasonable proxy for "this attempt was granted". It is not.
## Every test here is built so that at least one such proxy gives the wrong answer,
## and only the record's `outcome_granted` flag gives the right one.


func _actor() -> Actor:
	var actor := Actor.new(&"once_only_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	inventory.add(def, quantity)


func _prepare(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		var guard := 0
		while actor.meridians.refine_meridian(meridian_id, seed.required_refinement) and guard < 32:
			guard += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	var meditate_guard := 0
	while (
		meditate_guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate_guard += 1
		BodyTraining.meditate(actor, 1.0)
	_stock(actor, seed.breakthrough_item)
	return seed


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The chance a prepared actor commits against, read once from one fixture.
##
## Rebuilding a prepared body is the expensive part of these tests (a meditate
## ladder up to the realm's insight floor), so a per-candidate probe over actors
## costs minutes. The prepared body is deterministic, so one read of the chance
## fixes the search and the rest is pure RNG.
func _committed_chance() -> float:
	var probe := _actor()
	if _prepare(probe) == null:
		return 0.0
	var started := BodyAdvancement.start_attempt(probe)
	if started == null:
		return 0.0
	return float(started.preparation.get("chance", 0.0))


## The smallest seed whose first roll beats / does not beat `chance`.
func _seed_beating(chance: float) -> int:
	for candidate in range(1, 256):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if rng.randf() < chance:
			return candidate
	return 0


func _seed_losing(chance: float) -> int:
	for candidate in range(1, 256):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if rng.randf() >= chance:
			return candidate
	return 0


## Commit an attempt whose committed chance and roll both win.
func _granted_attempt(actor: Actor) -> BodyAttempt:
	var chance := _committed_chance()
	assert_ne(chance, 0.0, "the fixture commits against a real chance")
	var winning := _seed_beating(chance)
	assert_ne(winning, 0, "a winning seed exists for this fixture")
	_prepare(actor)
	var rng := _rng(winning)
	var started := BodyAdvancement.start_attempt(actor, rng)
	assert_ne(started == null, true, "attempt started")
	return started


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
##   - keyed on path PROGRESS, which advance zeroes on success: progress is still
##     at its pre-attempt value here, so such a guard would not fire at all;
##   - keyed on the rank EQUALING the target: it matches immediately, so the guard
##     fires and the attempt looks granted — but nothing was granted, so the pill
##     `start` already spent is unaccounted for and the record lies;
##   - keyed on the status alone: `committed` is active, so nothing fires.
##
## Only the attempt's OWN `outcome_granted` flag answers this correctly: it is
## false, so the attempt is stale, and `resolve_attempt` takes the stale branch.
func test_an_attempt_already_at_its_target_is_cancelled_not_treated_as_granted() -> void:
	var actor := _actor()
	var started := _granted_attempt(actor)
	assert_eq(started.target_rank, &"foundation", "the attempt names the realm it fought for")
	assert_eq(started.outcome_granted, false, "nothing granted yet")

	# The path arrives at the attempt's target by some other route while the
	# attempt is still committed. Progress is untouched: only the rank moved.
	actor.path(BodyPath.PATH_ID).rank_id = started.target_rank
	var stale := BodyAdvancement.attempt(actor)
	assert_eq(stale.is_active(), true, "still an active attempt")
	assert_eq(stale.outcome_granted, false, "still not granted")

	var physique := actor.stats.get_base(Stat.PHYSIQUE)
	assert_eq(BodyAdvancement.resolve_attempt(actor, _rng(8)), false, "no award")
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE), physique, "the award was NOT granted a second time"
	)
	assert_eq(
		BodyAdvancement.attempt(actor).status,
		BodyAttempt.STATUS_CANCELLED,
		"cancelled rather than marked granted: no trial ran"
	)
	assert_eq(
		BodyAdvancement.attempt(actor).outcome_granted,
		false,
		"the record does not claim an outcome it never had"
	)


## The mirror of the test above, and the only way to observe the guard firing on
## the flag ALONE: a record whose flag is set while the actor still stands in the
## SOURCE realm. `resolve_attempt` must short-circuit and report the same answer,
## granting nothing and advancing nothing.
##
## A guard keyed on progress cannot pass this: progress is at the target's
## requirement, not zero. A guard keyed on the rank cannot either: the rank is
## still the source. Only the flag is true here, so only the flag can produce this
## outcome.
func test_a_flagged_attempt_short_circuits_before_any_work() -> void:
	var actor := _actor()
	var started := _granted_attempt(actor)
	var physique := actor.stats.get_base(Stat.PHYSIQUE)
	var progress := actor.path(BodyPath.PATH_ID).progress
	assert_eq(progress > 0.0, true, "progress is not zero: a progress proxy cannot pass this")
	assert_eq(
		actor.path(BodyPath.PATH_ID).rank_id,
		&"qi_refining",
		"and the rank is still the source, so a rank proxy cannot either"
	)

	started.outcome_granted = true
	actor.set_module_data(BodyAdvancement.ATTEMPT_KEY, started.to_dict())
	assert_eq(BodyAdvancement.resolve_attempt(actor, _rng(12)), true, "granted, as flagged")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), physique, "nothing actually granted")
	assert_eq(
		actor.path(BodyPath.PATH_ID).rank_id,
		&"qi_refining",
		"and no advance either: the flag short-circuits before any of the work"
	)
	assert_almost_eq(actor.path(BodyPath.PATH_ID).progress, progress, "progress untouched", 0.0001)


## The case the guarantee is actually for. The award is a cumulative
## `set_base(get_base + reward)`, so a second resolve of the same record pays the
## realm's rewards twice. Resolving a granted attempt must report the same answer
## and change nothing at all.
func test_resolving_a_granted_attempt_again_pays_nothing() -> void:
	var actor := _actor()
	var started := _granted_attempt(actor)
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var fibres := actor.stats.get_base(&"muscle_fiber")
	assert_eq(BodyAdvancement.resolve_attempt(actor), true, "first resolve grants")
	var after_first := actor.stats.get_base(Stat.PHYSIQUE)
	assert_eq(after_first > before, true, "the award landed")
	var rank := actor.path(BodyPath.PATH_ID).rank_id
	# The pool is emptied on grant; capture it rather than asserting full/empty,
	# since `synchronize` resizes the reservoir to the realm just entered.
	# `AcupointSet` deliberately does not hand the pool out (it mediates access),
	# so the reservoir is read off the actor's resources, not off the huyệt set.
	var reservoir: ResourcePool = actor.resource(BodyStats.BODY_INTEGRITY)
	assert_ne(reservoir, null, "the body carries a reservoir")
	var drained: float = reservoir.current

	assert_eq(
		BodyAdvancement.resolve_attempt(actor), true, "second resolve reports the same answer"
	)
	assert_almost_eq(actor.stats.get_base(Stat.PHYSIQUE), after_first, "physique paid once")
	assert_almost_eq(
		actor.stats.get_base(&"muscle_fiber"), fibres + 1.0, "every reward key paid once"
	)
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, rank, "still exactly one realm on")
	assert_almost_eq(reservoir.current, drained, "the reservoir was not drained twice")


## A failed attempt grants nothing, and resolving it again must not turn it into a
## grant — a second resolve of a `failed` record is not an active attempt.
func test_resolving_a_failed_attempt_again_grants_nothing() -> void:
	var actor := _actor()
	var chance := _committed_chance()
	assert_ne(chance, 0.0, "the fixture commits against a real chance")
	var losing := _seed_losing(chance)
	assert_ne(losing, 0, "a losing seed exists for this fixture")
	_prepare(actor)
	# A deviation costs the shared reservoir, not a base stat, so that is what
	# proves the trial actually ran and applied its wound.
	var integrity: float = actor.resource(BodyStats.BODY_INTEGRITY).current
	var points: AcupointSet = actor.component(&"acupoints")
	assert_ne(BodyAdvancement.start_attempt(actor, _rng(losing)) == null, true, "attempt started")
	assert_eq(BodyAdvancement.resolve_attempt(actor), false, "the trial deviated")
	var failed := BodyAdvancement.attempt(actor)
	assert_eq(failed.status, BodyAttempt.STATUS_FAILED, "status is failed")
	assert_eq(failed.trial_complete, true, "and the trial ran")
	var wounded: float = actor.resource(BodyStats.BODY_INTEGRITY).current
	assert_eq(wounded < integrity, true, "the deviation cost integrity")
	assert_eq(points.blocked_count() >= 1, true, "and jammed a huyệt")
	assert_eq(BodyAdvancement.resolve_attempt(actor), false, "second resolve grants nothing")
	var after_second: float = actor.resource(BodyStats.BODY_INTEGRITY).current
	assert_almost_eq(after_second, wounded, "a failed attempt is not re-applied")
	assert_eq(points.blocked_count() >= 1, true, "still exactly one wound")


## The flag survives the round trip, which is what makes the guarantee hold across
## a save. A payload that lost `outcome_granted` would let a reload pay the same
## award a second time.
func test_the_once_only_flag_survives_save_and_load() -> void:
	var actor := _actor()
	_granted_attempt(actor)
	assert_eq(BodyAdvancement.resolve_attempt(actor), true, "resolved as a success")
	var after_first := actor.stats.get_base(Stat.PHYSIQUE)
	var fibres := actor.stats.get_base(&"muscle_fiber")
	var rank := actor.path(BodyPath.PATH_ID).rank_id

	var restored := Actor.from_dict(actor.to_dict())
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	var reloaded := BodyAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "the record came back")
	assert_eq(reloaded.outcome_granted, true, "the once-only flag came back with it")
	assert_eq(BodyAdvancement.resolve_attempt(restored), true, "same answer after the reload")
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE), after_first, "and still no second award"
	)
	assert_eq(restored.stats.get_base(&"muscle_fiber"), fibres, "no reward key paid twice")
	assert_eq(restored.path(BodyPath.PATH_ID).rank_id, rank, "still exactly one realm on")
