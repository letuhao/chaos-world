extends TestCase

## ADR 0028: the breakthrough attempt lifecycle. Preview must be side-effect
## free, an attempt has identity and survives a save, costs are consumed once,
## and a deviation is recoverable.


func _actor() -> Actor:
	var actor := Actor.new(&"attempt_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	# Assert, do not assume: a missing inventory aborts the caller mid-assertion
	# and the test is then reported as passing.
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	inventory.add(def, quantity)


## Bring the actor to the brink of the next realm through public actions.
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


# --- Preview ----------------------------------------------------------------


func test_preview_without_a_body_path_is_not_ready() -> void:
	var actor := Actor.new(&"pathless")
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], false, "no path, not ready")
	assert_ne(preview["unmet"], [], "reason is reported")


func test_preview_reports_unmet_before_preparation() -> void:
	var actor := _actor()
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], false, "not ready yet")
	assert_eq(preview["target"], &"foundation", "targets the next realm")
	assert_ne(preview["unmet"], [], "unmet list is populated")


func test_preview_does_not_mutate_anything() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY).current
	var rank := actor.path(BodyPath.PATH_ID).rank_id
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], true, "ready once prepared")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, rank, "rank unchanged")
	assert_almost_eq(
		actor.resource(BodyStats.BODY_INTEGRITY).current, integrity, "integrity unchanged"
	)
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), pills, "pill untouched")


func test_preview_is_stable_across_repeated_calls() -> void:
	var actor := _actor()
	_prepare(actor)
	var first := BodyAdvancement.preview(actor)
	var second := BodyAdvancement.preview(actor)
	assert_eq(first["chance"], second["chance"], "chance does not drift")
	assert_eq(first["unmet"], second["unmet"], "unmet list does not drift")


func test_preview_at_the_terminal_realm_is_not_ready() -> void:
	var actor := _actor()
	actor.path(BodyPath.PATH_ID).rank_id = &"primordial_origin"
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["ready"], false, "nowhere higher to go")
	assert_eq(preview["target"], &"", "no target realm")


# --- Start ------------------------------------------------------------------


func test_start_attempt_is_blocked_before_preparation() -> void:
	assert_eq(BodyAdvancement.start_attempt(_actor()), &"", "unprepared, no attempt")


func test_start_attempt_records_identity_and_consumes_one_pill() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 2, "two pills in hand")
	var attempt_id := BodyAdvancement.start_attempt(actor)
	assert_ne(attempt_id, &"", "attempt started")
	var attempt := actor.get_module_data(&"body_attempt")
	assert_eq(attempt.get("id"), attempt_id, "attempt id matches")
	assert_eq(attempt.get("path_id"), String(BodyPath.PATH_ID), "path recorded")
	assert_eq(attempt.get("source"), String(&"qi_refining"), "source recorded")
	assert_eq(attempt.get("target"), String(&"foundation"), "target recorded")
	assert_eq(attempt.get("pill"), String(seed.breakthrough_item), "pill recorded")
	assert_eq(attempt.get("status"), "pending", "attempt is pending")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 1, "exactly one pill spent")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"qi_refining", "no advance yet")


func test_only_one_attempt_is_active_at_a_time() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	assert_ne(BodyAdvancement.start_attempt(actor), &"", "first attempt started")
	assert_eq(BodyAdvancement.start_attempt(actor), &"", "second attempt refused")
	# The refusal must not spend another pill.
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 1, "no extra pill spent")


# --- Resolve ----------------------------------------------------------------


func test_resolve_without_an_attempt_is_a_noop() -> void:
	assert_eq(BodyAdvancement.resolve_attempt(_actor()), false, "nothing to resolve")


## Resolve under a seeded RNG until one attempt succeeds; preparation between
## attempts is the recovery a deviation requires.
func _resolve_until_success(actor: Actor, attempts: int = 32) -> bool:
	var rng := RandomNumberGenerator.new()
	for attempt in attempts:
		var seed := _prepare(actor)
		if seed == null:
			return false
		_stock(actor, seed.breakthrough_item, 1)
		if BodyAdvancement.start_attempt(actor) == &"":
			return false
		rng.seed = attempt + 1
		if BodyAdvancement.resolve_attempt(actor, rng):
			return true
	return false


func test_resolve_advances_and_clears_the_attempt() -> void:
	var actor := _actor()
	assert_eq(_resolve_until_success(actor), true, "an attempt resolved successfully")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"foundation", "realm advanced")
	assert_eq(actor.get_module_data(&"body_attempt").is_empty(), true, "attempt cleared")
	# Entering a realm never grants its milestone; only training while in it does.
	# (`test_milestone_grants_physique_once` covers the grant itself.)
	var progress: BodyProgress = actor.component(&"body_progress")
	assert_eq(progress.is_complete(&"foundation"), false, "entry grants no milestone")
	assert_eq(
		progress.is_complete(&"qi_refining"), false, "direct channel setup is not a training action"
	)


func test_failed_attempt_is_recoverable() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	var deviated := false
	var damaged_channel: StringName = &""
	for attempt in 64:
		var seed := _prepare(actor)
		if seed == null:
			break
		_stock(actor, seed.breakthrough_item, 1)
		if BodyAdvancement.start_attempt(actor) == &"":
			break
		var before := actor.path(BodyPath.PATH_ID).rank_id
		rng.seed = attempt + 1
		if BodyAdvancement.resolve_attempt(actor, rng):
			assert_eq(actor.path(BodyPath.PATH_ID).rank_id != before, true, "a success advances")
			continue
		deviated = true
		damaged_channel = seed.required_meridians[0]
		break
	assert_eq(deviated, true, "a deviation resolved as a failure")
	assert_eq(actor.get_module_data(&"body_attempt").is_empty(), true, "failed attempt cleared")
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.blocked_count() >= 1, true, "an acupoint was blocked")
	assert_eq(actor.meridians.get_meridian(damaged_channel).is_injured(), true, "channel damaged")
	# Re-preparing repairs the body: a deviation costs progress, never a body part.
	assert_ne(_prepare(actor), null, "prepared again after the deviation")
	assert_eq(points.blocked_count(), 0, "blockages cleared")
	assert_eq(actor.meridians.get_meridian(damaged_channel).is_injured(), false, "injury repaired")
	assert_eq(points.is_full(), true, "reservoir refilled")


## Stock the pill for whichever realm the actor is now standing in.
func _body_pill(actor: Actor) -> void:
	var seed := BodyRealmSeed.for_realm(actor.path(BodyPath.PATH_ID).rank_id)
	if seed != null:
		_stock(actor, seed.breakthrough_item, 1)


func test_resolve_aborts_when_the_stored_target_no_longer_matches() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	assert_ne(BodyAdvancement.start_attempt(actor), &"", "attempt started")
	# Something else moved the actor on; the stale attempt must not fire.
	actor.path(BodyPath.PATH_ID).rank_id = &"core_formation"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(BodyAdvancement.resolve_attempt(actor, rng), false, "stale attempt aborted")
	assert_eq(actor.get_module_data(&"body_attempt").is_empty(), true, "stale attempt cleared")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"core_formation", "rank untouched")


# --- Milestones ------------------------------------------------------------


## A milestone is the once-only payoff for training while in a realm. It was a
## write-only flag; now it grants physique and refuses to grant twice.
func test_milestone_grants_physique_once() -> void:
	var actor := _actor()
	var seed := BodyRealmSeed.for_realm(&"qi_refining")
	var progress: BodyProgress = actor.component(&"body_progress")
	_stock(actor, seed.strengthening_item)
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	assert_eq(BodyTraining.strengthen(actor, &"lung"), true, "channel trained")
	var granted := seed.integrity_maximum * BodyProgress.MILESTONE_PHYSIQUE_RATIO
	assert_almost_eq(
		actor.stats.get_base(Stat.PHYSIQUE) - before, granted, "milestone granted physique"
	)
	assert_eq(progress.is_complete(&"qi_refining"), true, "milestone recorded")
	# Training again must not pay a second time.
	var after_first := actor.stats.get_base(Stat.PHYSIQUE)
	for _i in 4:
		_stock(actor, seed.strengthening_item)
		BodyTraining.strengthen(actor, &"lung")
	assert_almost_eq(actor.stats.get_base(Stat.PHYSIQUE), after_first, "milestone never pays twice")


## Loading a save must not re-award every milestone's bonus.
func test_milestone_bonuses_are_not_reawarded_on_load() -> void:
	var actor := _actor()
	var seed := BodyRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.strengthening_item)
	BodyTraining.strengthen(actor, &"lung")
	var physique := actor.stats.get_base(Stat.PHYSIQUE)
	var restored := Actor.from_dict(actor.to_dict())
	# Re-attach the modules the composition root owns, including the inventory:
	# without `ItemsApi.attach` the restock below silently aborts the test.
	BodyCultivationApi.attach(restored)
	ItemsApi.attach(restored)
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE), physique, "load did not re-award the milestone"
	)
	var progress: BodyProgress = restored.component(&"body_progress")
	assert_eq(progress.is_complete(&"qi_refining"), true, "milestone survived the load")
	_stock(restored, seed.strengthening_item)
	BodyTraining.strengthen(restored, &"lung")
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE), physique, "still no second payout after load"
	)


# --- Risk and resonance ----------------------------------------------------


## Comprehension is the entry GATE, so if it also decided the roll then every
## attempt past R5 would be a certain success and the deviation loop could never
## fire. These assert the roll is independent of it.
func test_chance_does_not_depend_on_comprehension() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var before := float(BodyAdvancement.preview(actor)["chance"])
	actor.stats.set_base(Stat.COMPREHENSION, actor.stats.get_base(Stat.COMPREHENSION) * 4.0)
	var after := float(BodyAdvancement.preview(actor)["chance"])
	assert_almost_eq(after, before, "comprehension does not move the roll")


func test_chance_respects_the_authored_ceiling() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	var chance := float(BodyAdvancement.preview(actor)["chance"])
	assert_eq(chance <= seed.chance_cap, true, "chance never exceeds the realm ceiling")
	assert_eq(chance >= seed.chance_base, true, "chance is at least the realm floor")
	assert_eq(chance < 1.0, true, "no realm is a guaranteed success")


## Every realm must leave real risk on the table, or the deviation/recovery
## system is unreachable for that realm.
func test_every_realm_leaves_breakthrough_risk() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var perfect_quality := seed.quality_target
		var worst_case := seed.chance_base + perfect_quality * 0.5
		var effective := minf(worst_case, seed.chance_cap)
		assert_eq(effective < 0.95, true, "realm %s can still fail with perfect huyệt" % realm.id)


func test_resonance_lifts_the_meridian_network_from_the_seed() -> void:
	var actor := _actor()
	actor.path(BodyPath.PATH_ID).rank_id = &"earth_immortal"
	actor.meridians.unlock_for_realm(&"earth_immortal")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	actor.mark_stats_dirty()
	var before := actor.meridians.get_power_bonus()
	# R19 is the first resonant realm: rank 1, so a 5% lift on everything.
	BodyTraining.synchronize(actor)
	assert_eq(actor.meridians.resonance_rank, 1, "R19 sets resonance rank 1")
	var after := actor.meridians.get_power_bonus()
	assert_almost_eq(after, before * 1.05, "resonance lifts the network")


# --- Persistence ------------------------------------------------------------


func test_a_pending_attempt_survives_save_and_load() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	var attempt_id := BodyAdvancement.start_attempt(actor)
	assert_ne(attempt_id, &"", "attempt started")
	var restored := Actor.from_dict(actor.to_dict())
	var attempt := restored.get_module_data(&"body_attempt")
	assert_eq(attempt.get("id"), attempt_id, "attempt id survived")
	assert_eq(attempt.get("status"), "pending", "still pending after load")
	assert_eq(attempt.get("target"), String(&"foundation"), "target survived")
	# Re-attach the module as the composition root would, then resolve.
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	var rng := RandomNumberGenerator.new()
	var advanced := false
	for attempt_index in 32:
		_prepare(restored)
		_body_pill(restored)
		BodyAdvancement.start_attempt(restored)
		rng.seed = attempt_index + 1
		if BodyAdvancement.resolve_attempt(restored, rng):
			advanced = true
			break
	assert_eq(advanced, true, "restored actor can still resolve an attempt")
	assert_eq(restored.path(BodyPath.PATH_ID).rank_id, &"foundation", "restored actor advanced")
