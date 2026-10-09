extends TestCase

## ADR 0028: the breakthrough attempt lifecycle. Preview must be side-effect
## free, an attempt has identity and survives a save, costs are consumed once,
## and a deviation is recoverable.
##
## The lifecycle is the only implementation: `try_breakthrough` is the same two
## calls, so a single press and a save-spanning attempt cannot diverge. What
## these tests pin is the *record*, not the outcome — the outcome is a roll.

const Play := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")


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
	# BL-0951: a real run's huyệt saturate at the STANDING realm's authored target
	# (`BodyTraining.strengthen` trains them there unconditionally), so the fixture
	# mirrors that level — at the target realm's bare requirement the departures would
	# snapshot 0.0 and the foundation wall would refuse a state a player cannot hold.
	var source := BodyRealmSeed.for_realm(state.rank_id)
	var point_level := seed.quality_required
	if source != null:
		point_level = maxf(point_level, source.quality_target)
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, point_level)
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
	assert_eq(preview["attempt"], "", "no attempt in flight")


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


## The preview is the read side of the lifecycle, so it must name the attempt in
## flight — otherwise a screen cannot tell "breakthrough is available" from "a pill
## is already spent, resolve it".
func test_preview_names_the_attempt_in_flight() -> void:
	var actor := _actor()
	_prepare(actor)
	var committed := BodyAdvancement.start_attempt(actor)
	assert_ne(committed == null, true, "attempt started")
	var preview := BodyAdvancement.preview(actor)
	assert_eq(preview["attempt"], String(committed.attempt_id), "the preview names it")
	# A resolved attempt is no longer in flight and must stop being advertised.
	# Which way the stored roll fell is irrelevant here and is not asserted.
	BodyAdvancement.resolve_attempt(actor)
	assert_eq(BodyAdvancement.preview(actor)["attempt"], "", "resolved: nothing in flight")


# --- Start ------------------------------------------------------------------


func test_start_attempt_is_blocked_before_preparation() -> void:
	assert_eq(BodyAdvancement.start_attempt(_actor()) == null, true, "unprepared, no attempt")


func test_start_attempt_records_identity_and_consumes_one_pill() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 2, "two pills in hand")
	var committed := BodyAdvancement.start_attempt(actor)
	assert_ne(committed == null, true, "attempt started")
	assert_eq(committed.path_id, BodyPath.PATH_ID, "path recorded")
	assert_eq(committed.actor_id, actor.id, "actor recorded")
	assert_eq(committed.source_rank, &"qi_refining", "source recorded")
	assert_eq(committed.target_rank, &"foundation", "target recorded")
	assert_eq(committed.seed_id, seed.id, "seed recorded")
	assert_eq(committed.status, BodyAttempt.STATUS_COMMITTED, "attempt is committed")
	assert_eq(committed.pill_consumed, true, "the spent pill is recorded")
	assert_eq(committed.outcome_granted, false, "nothing granted yet")
	assert_eq(committed.sequence, 1, "first attempt is sequence 1")
	# The persisted copy is the record, not a lossy summary of it.
	assert_eq(BodyAdvancement.attempt(actor).to_dict(), committed.to_dict(), "record round-trips")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 1, "exactly one pill spent")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"qi_refining", "no advance yet")


## The id must be derived from the actor and the sequence, not the wall clock: a
## `Time.get_ticks_msec()` id names a *different* attempt after every reload, so
## a save could never be traced back to the attempt that spent its pill.
func test_the_attempt_id_is_reproducible_not_wall_clock_derived() -> void:
	var actor := _actor()
	_prepare(actor)
	var first := BodyAdvancement.start_attempt(actor)
	assert_ne(first == null, true, "attempt started")
	assert_eq(
		first.attempt_id,
		BodyAttempt.make_id(actor.id, BodyPath.PATH_ID, 1),
		"the id is a pure function of actor, path and sequence"
	)
	BodyAdvancement.cancel(actor)
	# The first attempt spent the realm's pill; re-prepare so the second start is
	# refused for the right reason (sequence, not a missing item).
	_prepare(actor)
	var second := BodyAdvancement.start_attempt(actor)
	assert_ne(second == null, true, "second attempt started")
	assert_eq(second.sequence, 2, "the sequence advanced past the cancelled one")
	assert_ne(second.attempt_id, first.attempt_id, "a new attempt has a new id")


## The single-active-attempt rule, and the second half of it: the refusal must
## not spend a second pill.
func test_only_one_attempt_is_active_at_a_time() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	assert_ne(BodyAdvancement.start_attempt(actor) == null, true, "first attempt started")
	assert_eq(BodyAdvancement.start_attempt(actor) == null, true, "second attempt refused")
	assert_eq(ItemsApi.inventory(actor).count(seed.breakthrough_item), 1, "no extra pill spent")


## The resolved record is KEPT, so "is one in flight?" must key on the record's
## status, not on whether the bag is empty. Keying on emptiness made a kept
## record a permanent lockout: every retry after the first breakthrough was
## refused with no way out.
func test_a_terminal_record_does_not_lock_out_the_next_attempt() -> void:
	var actor := _actor()
	var resolved := false
	# Bounded by the seed space, not by hope: the lowest `chance_base` on the
	# ladder is 0.2580, so 32 independent draws all losing is 0.742^32 ~= 1e-10.
	for _attempt_index in 32:
		var prepared := _prepare(actor)
		if prepared == null:
			break
		_stock(actor, prepared.breakthrough_item, 1)
		if BodyAdvancement.start_attempt(actor) == null:
			break
		if BodyAdvancement.resolve_attempt(actor):
			resolved = true
			break
	assert_eq(resolved, true, "an attempt resolved")
	var record := BodyAdvancement.attempt(actor)
	assert_ne(record == null, true, "the resolved record is kept, not cleared")
	assert_eq(record.is_active(), false, "and it is not active")
	assert_eq(BodyAdvancement.active_attempt(actor) == null, true, "nothing is in flight")
	# The next realm's attempt must still be reachable.
	_prepare(actor)
	assert_ne(BodyAdvancement.start_attempt(actor) == null, true, "the next attempt starts")


## A two-phase attempt that skipped the re-entrancy guard could interleave with a
## cultivate/strengthen on the same huyệt set. `try_breakthrough` already held
## `busy`; `start_attempt` did not, so driving the two halves from a screen left
## the guard decorative.
func test_start_attempt_refuses_while_the_acupoints_are_busy() -> void:
	var actor := _actor()
	_prepare(actor)
	var points: AcupointSet = actor.component(&"acupoints")
	points.busy = true
	assert_eq(BodyAdvancement.start_attempt(actor) == null, true, "refused while busy")
	points.busy = false
	assert_ne(BodyAdvancement.start_attempt(actor) == null, true, "accepted once free")


# --- Resolve ----------------------------------------------------------------


func test_resolve_without_an_attempt_is_a_noop() -> void:
	assert_eq(BodyAdvancement.resolve_attempt(_actor()), false, "nothing to resolve")


## Commit and resolve until one attempt succeeds; preparation between attempts is
## the recovery a deviation requires.
##
## No generator, so each attempt draws its own seed — which is the point: this is
## the shipped lifecycle, and it is only reachable at all because a real press can
## now win. Bounded by the seed space: at the lowest authored `chance_base` (0.2580)
## 32 independent draws all losing is 0.742^32 ~= 1e-10.
func _resolve_until_success(actor: Actor, attempts: int = 32) -> bool:
	for _attempt_index in attempts:
		var seed := _prepare(actor)
		if seed == null:
			return false
		_stock(actor, seed.breakthrough_item, 1)
		if BodyAdvancement.start_attempt(actor) == null:
			return false
		if BodyAdvancement.resolve_attempt(actor):
			return true
	return false


func test_resolve_advances_and_records_the_outcome() -> void:
	var actor := _actor()
	assert_eq(_resolve_until_success(actor), true, "an attempt resolved successfully")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"foundation", "realm advanced")
	var record := BodyAdvancement.attempt(actor)
	assert_ne(record == null, true, "the record is kept")
	assert_eq(record.status, BodyAttempt.STATUS_SUCCESS, "status is success")
	assert_eq(record.outcome_granted, true, "the award is flagged granted")
	assert_eq(record.trial_complete, true, "the trial ran")
	assert_eq(record.is_resolved(), true, "terminal")
	# Entering a realm never grants its milestone; only training while in it does.
	# (`test_milestone_grants_physique_once` covers the grant itself.)
	var progress: BodyProgress = actor.component(&"body_progress")
	assert_eq(progress.is_complete(&"foundation"), false, "entry grants no milestone")
	assert_eq(
		progress.is_complete(&"qi_refining"), false, "direct channel setup is not a training action"
	)


func test_failed_attempt_is_recoverable() -> void:
	var actor := _actor()
	var deviated := false
	var damaged_channel: StringName = &""
	# Bounded by the seed space: at the best authored `chance_base` (0.4900) 64
	# independent draws all winning is 0.4900^64 ~= 1e-20.
	for _attempt_index in 64:
		var seed := _prepare(actor)
		if seed == null:
			break
		_stock(actor, seed.breakthrough_item, 1)
		if BodyAdvancement.start_attempt(actor) == null:
			break
		var before := actor.path(BodyPath.PATH_ID).rank_id
		if BodyAdvancement.resolve_attempt(actor):
			assert_eq(actor.path(BodyPath.PATH_ID).rank_id != before, true, "a success advances")
			continue
		deviated = true
		damaged_channel = seed.required_meridians[0]
		break
	assert_eq(deviated, true, "a deviation resolved as a failure")
	var record := BodyAdvancement.attempt(actor)
	assert_ne(record == null, true, "the record is kept")
	assert_eq(record.status, BodyAttempt.STATUS_FAILED, "status is failed")
	assert_eq(record.outcome_granted, false, "a deviation grants nothing")
	assert_eq(record.trial_complete, true, "but the trial did run")
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.blocked_count() >= 1, true, "an acupoint was blocked")
	assert_eq(actor.meridians.get_meridian(damaged_channel).is_injured(), true, "channel damaged")
	# Re-preparing repairs the body: a deviation costs progress, never a body part.
	assert_ne(_prepare(actor), null, "prepared again after the deviation")
	assert_eq(points.blocked_count(), 0, "blockages cleared")
	assert_eq(actor.meridians.get_meridian(damaged_channel).is_injured(), false, "injury repaired")
	var refilled: ResourcePool = actor.resource(BodyStats.BODY_INTEGRITY)
	assert_eq(refilled.ratio() >= 1.0, true, "reservoir refilled")


## An attempt whose target realm is no longer the one the actor would enter has
## to end without a deviation: nothing was rolled, so nothing is owed. Keying this
## on "the rank already equals the target" would mark it granted and pay an award
## for a trial that never happened.
func test_resolve_aborts_when_the_stored_target_no_longer_matches() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	var committed := BodyAdvancement.start_attempt(actor)
	assert_ne(committed == null, true, "attempt started")
	# Something else moved the actor on; the stale attempt must not fire.
	actor.path(BodyPath.PATH_ID).rank_id = &"core_formation"
	var record := BodyAdvancement.resolve_attempt(actor)
	assert_eq(record, false, "stale attempt aborted")
	var stored := BodyAdvancement.attempt(actor)
	assert_ne(stored == null, true, "the stale record is kept, not cleared")
	assert_eq(stored.status, BodyAttempt.STATUS_CANCELLED, "cancelled: no trial ran")
	assert_eq(stored.outcome_granted, false, "the record does not claim an outcome")
	assert_eq(stored.trial_complete, false, "and owes no deviation")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"core_formation", "rank untouched")


## The gate a save can invalidate. The attempt is committed with its tier gate
## open, then the gate shuts underneath it — the tribulation record or the
## inside world did not survive the round trip. Resolving anyway would roll for an
## outcome no gate permits.
##
## The status is the observable that separates the two designs. A gate that shut
## is CANCELLED: nothing was rolled, so no deviation is owed and no award is due.
## Rolling first and letting `try_advance_gated` refuse reports the same `false`,
## but records a FAILED attempt — telling the player it deviated, which it did
## not.
func test_resolve_cancels_when_the_tier_gate_shut_under_the_attempt() -> void:
	var actor := _actor()
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	var threshold := Breakthrough.IMMORTAL_REALM_THRESHOLD
	var source := realms[threshold - 1].id
	var target := realms[threshold]
	# Stand in the realm before the Immortal tier, then prepare for the tier's
	# first realm through the same helper every other fixture uses.
	actor.path(BodyPath.PATH_ID).rank_id = source
	actor.meridians.unlock_for_realm(source)
	# BL-0951: standing at R18 implies the climb that got here; backfill the history a
	# real walk would have snapshotted, or the foundation wall refuses an attempt this
	# test needs the gate to open for.
	Play.new().backfill_foundation(actor)
	# `_prepare` raises the quality of the points that EXIST but never grows the
	# set, and the gate reads every huyệt the current realm has unlocked. Sync
	# first, so the points R1..R17 introduced are present for `_prepare` to
	# train; otherwise the gate reports "quality below the realm requirement" for
	# points the actor has never heard of.
	BodyTraining.synchronize(actor)
	var seed := _prepare(actor)
	assert_ne(seed == null, true, "prepared for %s" % target.id)
	# R19's only live gate is the tribulation: `stage_met` short-circuits to true
	# at or below COMMIT_SEED, and `world_ok`/`ascension_ok` below COMMIT_MICRO.
	assert_eq(Breakthrough.inside_world_ok(actor, threshold), true, "no inside world needed yet")
	assert_eq(Breakthrough.world_ok(actor, threshold), true, "no created world needed yet")
	assert_eq(Breakthrough.ascension_ok(actor, threshold), true, "no ascent needed yet")
	assert_eq(Breakthrough.tribulation_ok(actor, threshold), false, "the tribulation is the gate")
	var fight := Breakthrough.begin_tribulation(actor, threshold)
	assert_ne(fight == null, true, "a tribulation was begun for the tier")
	var wave_guard := 0
	while Breakthrough.advance_tribulation(actor) and wave_guard < 64:
		wave_guard += 1
	Breakthrough.resolve_tribulation(actor, true)
	assert_eq(
		Breakthrough.tribulation_ok(actor, threshold), true, "the gate is open before it shuts"
	)
	_stock(actor, seed.breakthrough_item)
	var committed := BodyAdvancement.start_attempt(actor)
	assert_ne(committed == null, true, "attempt started with the gate open")
	assert_eq(committed.target_rank, target.id, "and it names the gated realm")
	# Shut the gate without touching the path the attempt named.
	actor.tribulation = null
	assert_eq(Breakthrough.tier_gates_met(actor, threshold), false, "the gate is now shut")
	var physique := actor.stats.get_base(Stat.PHYSIQUE)
	var progress := actor.path(BodyPath.PATH_ID).progress
	var blocked: int = (actor.component(&"acupoints") as AcupointSet).blocked_count()
	assert_eq(BodyAdvancement.resolve_attempt(actor), false, "the shut gate refuses")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), physique, "no award")
	assert_almost_eq(actor.path(BodyPath.PATH_ID).progress, progress, "progress untouched", 0.0001)
	assert_eq(
		(actor.component(&"acupoints") as AcupointSet).blocked_count(),
		blocked,
		"no deviation: nothing was rolled"
	)
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, source, "realm untouched")
	var stored := BodyAdvancement.attempt(actor)
	assert_ne(stored == null, true, "the record is kept")
	assert_eq(stored.status, BodyAttempt.STATUS_CANCELLED, "cancelled, not a deviation")
	assert_eq(stored.outcome_granted, false, "nothing granted")
	assert_eq(stored.trial_complete, false, "no trial ran")


func test_cancel_ends_the_attempt_without_a_deviation() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	_stock(actor, seed.breakthrough_item, 1)
	var committed := BodyAdvancement.start_attempt(actor)
	assert_ne(committed == null, true, "attempt started")
	var progress := actor.path(BodyPath.PATH_ID).progress
	var blocked: int = (actor.component(&"acupoints") as AcupointSet).blocked_count()
	assert_eq(BodyAdvancement.cancel(actor), true, "cancelled")
	var stored := BodyAdvancement.attempt(actor)
	assert_eq(stored.status, BodyAttempt.STATUS_CANCELLED, "cancelled")
	assert_eq(stored.outcome_granted, false, "nothing granted")
	assert_eq(
		(actor.component(&"acupoints") as AcupointSet).blocked_count(),
		blocked,
		"no deviation was applied"
	)
	assert_almost_eq(actor.path(BodyPath.PATH_ID).progress, progress, "progress untouched", 0.0001)
	assert_eq(BodyAdvancement.cancel(actor), false, "nothing left to cancel")


# --- The wired one-press path ------------------------------------------------


## The facade's `attempt_breakthrough` is what the breakthrough button calls, so
## it must go through the persisted lifecycle rather than a parallel
## implementation. If it ever stops doing so, this is the test that notices.
func test_the_one_press_path_goes_through_the_persisted_attempt() -> void:
	var actor := _actor()
	var advanced := false
	for attempt_index in 32:
		var seed := _prepare(actor)
		if seed == null:
			break
		_stock(actor, seed.breakthrough_item, 1)
		if BodyCultivationApi.attempt_breakthrough(actor):
			advanced = true
			break
	assert_eq(advanced, true, "a breakthrough went through")
	var record := BodyAdvancement.attempt(actor)
	assert_ne(record == null, true, "the one-press path left a record")
	assert_eq(record.outcome_granted, true, "and it is the granted one")
	assert_eq(record.is_active(), false, "no attempt left in flight")


## `busy` is what stops a body action interleaving on the same huyệt set. It was
## cleared on every exit of the old hand-rolled path; assert it is still cleared,
## including on the refusal path, so a refused breakthrough cannot wedge the actor.
## The return value is deliberately not asserted: it is a roll, and every exit
## must clear `busy` whichever way the roll went.
func test_the_one_press_path_leaves_the_acupoints_unbusy() -> void:
	var actor := _actor()
	var points: AcupointSet = actor.component(&"acupoints")
	BodyCultivationApi.attempt_breakthrough(actor)
	assert_eq(points.busy, false, "the refusal path cleared busy")
	_prepare(actor)
	BodyCultivationApi.attempt_breakthrough(actor)
	assert_eq(points.busy, false, "the accepted path cleared busy")
	# A wedged actor could never cultivate again, so prove it still can.
	assert_eq(BodyTraining.cultivate(actor, 25.0), true, "the actor is not wedged")


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
	_prepare(actor)
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
