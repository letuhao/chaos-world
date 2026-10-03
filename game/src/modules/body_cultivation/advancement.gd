class_name BodyAdvancement
extends RefCounted

## Body-cultivation breakthrough lifecycle (ADR 0015/0023/0028).
##
## A breakthrough is transactional: `preview` reports the conditions and
## consumes nothing, `start_attempt` validates, spends the realm pill exactly
## once and commits a persisted `BodyAttempt`, and `resolve_attempt` rolls that
## record into either an award or a recoverable deviation. Only one attempt is
## active per actor.
##
## The award is keyed on the record's identity (`outcome_granted`), not on the
## path's progress, so re-resolving one attempt can never grant twice. The roll
## reads the chance stored in the record's `preparation`, so an attempt that
## spans a save resolves against the body it paid for.
##
## `try_breakthrough` stays as the one-shot convenience wrapper over both steps
## and is the path the UI takes: it is the same two calls, so a saved-then-
## reloaded attempt and a single-press attempt cannot diverge.

const _ITEMS := preload("res://src/modules/items/api.gd")

## Module-owned attempt record. Serialized as raw data and rebuilt by this
## module, so core never imports this class.
const ATTEMPT_KEY := &"body_attempt"

## Acupoint quality buys breakthrough certainty: half a point of average
## quality is half a point of chance.
const QUALITY_TO_CHANCE := 0.5
const MIN_CHANCE := 0.05


## The single chance formula. It reads the target realm's authored
## `chance_base`/`chance_cap` and the actor's average acupoint quality.
##
## It deliberately does NOT read `Stat.BREAKTHROUGH_CHANCE`, because that stat is
## driven by comprehension and comprehension is the entry GATE: at attempt time
## `comprehension >= insight_required`, so `0.1 + 0.01 * insight_required` alone
## exceeded the 0.95 clamp from R5 on. Twenty-six of twenty-nine attempts were
## certain successes and the deviation/recovery loop could not fire (ADR 0028).
static func _chance(points: AcupointSet, seed: BodyRealmSeed) -> float:
	var avg_quality := 0.0 if points == null else points.average_quality()
	return clampf(seed.chance_base + avg_quality * QUALITY_TO_CHANCE, MIN_CHANCE, seed.chance_cap)


# --- Read side ---------------------------------------------------------------


## Preview the breakthrough without mutating anything. Returns a dictionary with:
##   - ready: bool — whether all conditions are met
##   - unmet: Array[String] — human-readable unmet conditions
##   - chance: float — evaluated breakthrough chance
##   - cost: StringName — breakthrough pill item id
##   - target: StringName — target realm id
##   - attempt: String — the active attempt's id, empty when none is in flight
static func preview(actor: Actor) -> Dictionary:
	var active := active_attempt(actor)
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return _refused(["No body path"], &"", active)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return _refused(["Already at highest realm"], &"", active)
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return _refused(["No realm seed"], &"", active)
	var condition := BodyBreakthroughCondition.new()
	var unmet: Array[String] = condition.describe_unmet(actor, state)
	var points: AcupointSet = actor.component(&"acupoints")
	return {
		"ready": unmet.is_empty(),
		"unmet": unmet,
		"chance": _chance(points, seed),
		"cost": seed.breakthrough_item,
		"target": target.id,
		"attempt": _id(active),
	}


## The preview's refusal shape, from one builder: a screen that reads `ready`
## must never have to probe whether `chance` or `target` is present.
static func _refused(unmet: Array[String], target: StringName, active: BodyAttempt) -> Dictionary:
	return {
		"ready": false,
		"unmet": unmet,
		"chance": 0.0,
		"cost": &"",
		"target": target,
		"attempt": _id(active),
	}


# --- Attempt record ----------------------------------------------------------


## The stored attempt record, terminal or not, or null when there is none.
static func attempt(actor: Actor) -> BodyAttempt:
	var stored: Variant = actor.get_module_data(ATTEMPT_KEY)
	if not stored is Dictionary or stored.is_empty():
		return null
	return BodyAttempt.from_dict(stored)


## The attempt currently in flight, or null. One at a time, per actor.
##
## A *terminal* record is not active: the resolved attempt is kept for its
## `outcome_granted` flag and its audit trail, and it must not block the next
## attempt. Keying "is one in flight?" on the raw bag instead made a kept record
## a permanent lockout.
static func active_attempt(actor: Actor) -> BodyAttempt:
	var stored := attempt(actor)
	if stored == null or not stored.is_active():
		return null
	return stored


static func _store(actor: Actor, value: BodyAttempt) -> void:
	actor.set_module_data(ATTEMPT_KEY, value.to_dict())


static func _id(value: BodyAttempt) -> String:
	return "" if value == null else String(value.attempt_id)


# --- Start -------------------------------------------------------------------


## Commit a breakthrough attempt: validate, spend the realm pill exactly once,
## and persist the record. Returns null when refused — an acupoint-consuming
## action holds the points, unprepared, no target realm, or another attempt is
## already active.
##
## Refusing while `busy` is what keeps a two-phase attempt from interleaving with
## `cultivate`/`strengthen`/`recover` on the same huyệt set. `try_breakthrough`
## holds `busy` across both halves and therefore calls `_start` directly.
static func start_attempt(actor: Actor, rng: RandomNumberGenerator = null) -> BodyAttempt:
	var points: AcupointSet = actor.component(&"acupoints")
	if points != null and points.busy:
		return null
	return _start(actor, rng)


static func _start(actor: Actor, rng: RandomNumberGenerator) -> BodyAttempt:
	# Face the tribulation owed for this path's next realm BEFORE validating anything
	# (ADR 0061), so R19-R30 are reachable by play rather than only by a test. Every
	# entry into an attempt runs through here — `start_attempt` and the one-shot
	# `try_breakthrough` — so the wave is charged once per committed attempt. The
	# return is discarded on purpose: a wave never opens the gate.
	Breakthrough.face_tribulation(actor, BodyPath.PATH_ID, rng)
	if active_attempt(actor) != null:
		return null
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return null
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	var condition := BodyBreakthroughCondition.new()
	if not condition.can_breakthrough(actor, state, {}):
		return null
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return null
	var sequence := _next_sequence(actor)
	var committed := (
		BodyAttempt
		. new(
			BodyAttempt.make_id(actor.id, BodyPath.PATH_ID, sequence),
			actor.id,
			BodyPath.PATH_ID,
			state.rank_id,
			target.id,
			seed.id,
		)
	)
	committed.sequence = sequence
	committed.pill_consumed = true
	committed.costs_paid = true
	# The attempt is rolled against the preparation it paid for, never against a
	# later one, and the chance is fixed here instead of drifting at resolve time.
	var points: AcupointSet = actor.component(&"acupoints")
	committed.rng_state = 0 if rng == null else rng.seed
	committed.preparation = {
		"chance": _chance(points, seed),
		"average_quality": 0.0 if points == null else points.average_quality(),
		"integrity_ratio":
		(
			0.0
			if actor.resource(BodyStats.BODY_INTEGRITY) == null
			else actor.resource(BodyStats.BODY_INTEGRITY).ratio()
		),
		"progress": state.progress,
		"pill": String(seed.breakthrough_item),
	}
	committed.commit()
	_store(actor, committed)
	actor.mark_stats_dirty()
	return committed


static func _next_sequence(actor: Actor) -> int:
	var previous := attempt(actor)
	return 1 if previous == null else previous.sequence + 1


# --- Resolve -----------------------------------------------------------------


## Resolve the stored attempt: roll it, then grant its award once or apply its
## recoverable deviation. True only when the outcome was granted, so re-resolving
## a granted attempt is a no-op that reports the same answer.
static func resolve_attempt(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var committed := attempt(actor)
	if committed == null:
		return false
	# Once-only award: keyed on the record's identity, not on the path's
	# progress having been reset (ADR 0029).
	if committed.outcome_granted:
		return true
	if not committed.is_active():
		return false
	var state := actor.path(BodyPath.PATH_ID)
	# The attempt names its own target: the realm it is trying to enter, never
	# the one after it.
	var target := RealmDefaults.ladder().realm(committed.target_rank)
	if state == null or target == null or state.rank_id != committed.source_rank:
		# Something else moved this actor on, so the trial never ran.
		_end(actor, committed, false)
		return false
	var seed := BodyRealmSeed.for_realm(committed.target_rank)
	var points: AcupointSet = actor.component(&"acupoints")
	if seed == null or points == null:
		_end(actor, committed, false)
		return false
	# The tier gates are a *prerequisite*, not an outcome, and they are the one
	# thing a save can invalidate underneath an attempt: a tribulation record or
	# an inside world that did not survive the round trip leaves the gate shut.
	# Refuse before rolling, so a stale gate costs no deviation and no award.
	if not Breakthrough.tier_gates_met(actor, target.index):
		_end(actor, committed, false)
		return false
	committed.mark_trial_complete()
	var generator := rng if rng != null else _replay(committed)
	var chance := float(committed.preparation.get("chance", _chance(points, seed)))
	if generator.randf() >= chance:
		_deviate(actor, state, seed, points, generator)
		_end(actor, committed, false)
		return false
	# The gate is the last thing that can still refuse, and a refusal must leave
	# the actor exactly as it was found: no realm, no rewards, no drained pool.
	# Granting first would pay the award for a breakthrough that never happened.
	if not Breakthrough.try_advance_gated(actor, BodyPath.PATH_ID):
		_end(actor, committed, false)
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# Drain the shared pool on success — the breakthrough consumes stored essence.
	points.drain(seed.integrity_maximum)
	BodyTraining.synchronize(actor)
	# The milestone is NOT marked here. It is granted by training while in the
	# realm, so its physique bonus is earned rather than free (ADR 0023). It is
	# also self-consistent: the gate for the next realm demands refinement equal
	# to this realm's cap, which is only reachable by strengthening here.
	# Entering a high tier *commits* the milestone it produces; the next tier
	# gates on it (ADR 0018-0021).
	WorldAnchor.commit(actor, target.index)
	_end(actor, committed, true)
	return true


## End the attempt and persist the record. `granted` sets the once-only outcome
## flag; an attempt whose trial never ran is cancelled, because no deviation is
## owed.
static func _end(actor: Actor, committed: BodyAttempt, granted: bool) -> void:
	if granted:
		committed.succeed()
	elif committed.trial_complete:
		committed.fail()
	else:
		committed.cancel()
	_store(actor, committed)
	actor.mark_stats_dirty()


## Abandon the attempt in flight. The pill stays spent and no deviation is owed:
## the trial never ran. False when there is no attempt to abandon.
static func cancel(actor: Actor) -> bool:
	var committed := active_attempt(actor)
	if committed == null:
		return false
	_end(actor, committed, false)
	return true


## The generator the record was committed with, so a persisted attempt resolves
## to the same outcome after a reload instead of rerolling.
static func _replay(committed: BodyAttempt) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = committed.rng_state
	return generator


# --- Convenience -------------------------------------------------------------


## One-shot breakthrough: commit and resolve in a single call. This is the wired
## entry point, and it is the *same two calls* the two-phase lifecycle makes —
## there is no second implementation that can drift from the first.
##
## `busy` is held across both halves so a body cultivation action cannot
## interleave on the same huyệt set, and cleared on every exit.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null or points.busy:
		return false
	points.busy = true
	var committed := _start(actor, rng)
	if committed == null:
		points.busy = false
		return false
	var granted := resolve_attempt(actor, rng)
	points.busy = false
	return granted


## Deviation: lose half the progress, jam a huyệt and tear the channel the
## actor trained deepest, and cost integrity (ADR 0015/0023).
static func _deviate(
	actor: Actor,
	state: PathState,
	seed: BodyRealmSeed,
	points: AcupointSet,
	rng: RandomNumberGenerator
) -> void:
	state.progress *= 0.5
	var torn := _deepest_required_channel(actor, seed)
	# Both halves of the wound land on the same meridian so the damage has a
	# location.
	BodyDeviationJam.on_channel(actor, points, torn, rng)
	if torn != &"":
		actor.meridians.damage_meridian(torn)
	actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)
	actor.mark_stats_dirty()


## The channel a deviation tears: the required one the actor trained deepest.
## Falling back to `required_meridians[0]` always chose lung, for every realm,
## so the wound had no location and no player-visible cause.
static func _deepest_required_channel(actor: Actor, seed: BodyRealmSeed) -> StringName:
	var best: StringName = &""
	var best_refinement := -1
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.refinement > best_refinement:
			best_refinement = channel.refinement
			best = meridian_id
	if best != &"":
		return best
	return seed.required_meridians[0] if not seed.required_meridians.is_empty() else &""
