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
## spans a save resolves against the body it paid for — and the seed that decides
## the roll lives in the record too (`BodyAttemptRoll`), so it resolves to the same
## outcome as well.
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

## The fate a body breakthrough earns (DEF-0106).
##
## `reborn_in_a_lesser_vessel`, chosen from the fate's OWN text: "Came back after a
## failure at the barrier in a body the sect records as a downgrade. The technique
## survived." A body breakthrough IS crossing the barrier and being re-seated, and
## the `seed.rewards` loop a few lines below is the stat award this very grant
## accompanies — so the fate and the numbers describe one event rather than two.
##
## It is the one fate `the_chosen_instrument` names in its own `requires_fates`, and
## `character_creation_flow.ARRIVAL_FATES` already supplies it at creation for that
## origin. So `earn_fate` being exactly-once is load-bearing here rather than merely
## tidy: creation and this path can both reach the same player, and ADR 0065's rule
## that a second earn pays nothing is what stops the arrival table from paying a
## destiny's own prerequisite twice.
const FATE_BARRIER := &"reborn_in_a_lesser_vessel"

## The `source` string this path's earn carries, in the shape `QuestGrants
## .FATE_SOURCE_PREFIX + quest_id` and `EventDef.fate_source()` both build: it names
## the SYSTEM that earned the fate and the decision point, never the fate id itself
## (ADR 0065 on id namespaces).
const EARN_SOURCE := "body_breakthrough"


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
## **The body answers first (ADR 0109).** A body plan that closes the body path, or one whose
## `realm_ceiling` sits above the realm being entered, is refused HERE, before any other
## check and before anything is spent. It sits here rather than in the facade because this
## is the one call both halves of the durable lifecycle make: `begin_breakthrough` calls it
## and so does the one-shot `try_breakthrough`, so a gate one layer up left
## `begin_breakthrough`/`resolve_breakthrough` — the documented two-phase path where a pill
## is spent and the attempt persisted across a save — completely ungated. A rule a caller
## can walk around is not a rule. It is a precondition and never a modifier.
##
## Refusing while `busy` is what keeps a two-phase attempt from interleaving with
## `cultivate`/`strengthen`/`recover` on the same huyệt set. `try_breakthrough`
## holds `busy` across both halves and therefore calls `_start` directly — which reads
## the same gate, so holding `busy` buys no way around it.
##
## **`rng` is an optional SEED SOURCE, and the record is what resolves.** Whatever it
## is handed, the seed this call stores is the only randomness the attempt will ever
## have, and `resolve_attempt` replays it without taking a generator of its own. The
## shipped facade passes none, so a real player press draws its own seed — see
## `BodyAttemptRoll` for why the seed is drawn here rather than at resolve, and why it
## can never be the constant this module used to write.
static func start_attempt(actor: Actor, rng: RandomNumberGenerator = null) -> BodyAttempt:
	var points: AcupointSet = actor.component(&"acupoints")
	if points != null and points.busy:
		return null
	return _start(actor, rng)


static func _start(actor: Actor, rng: RandomNumberGenerator) -> BodyAttempt:
	if not _body_allows(actor):
		return null
	# A REFUSAL COSTS NOTHING, SO THE LOCKOUT IS CHECKED BEFORE THE TOLL.
	# `face_tribulation` descends a wave and `Tribulation.fight_wave` charges
	# `WAVE_TOLL` (1.0 COMPREHENSION, and comprehension is this path's own entry
	# gate), so a press refused for the lockout must not have descended one first.
	#
	# **LATENT, NOT OBSERVED.** No shipped path reaches the pair today: an attempt is
	# only committed once `can_breakthrough` has already passed the tribulation clause,
	# and nothing on the body screen can un-win a tribulation, so the gate is open
	# whenever the lockout fires and `face_tribulation` is a no-op. The tribulation
	# screen can leave it shut — `Breakthrough.cancel_tribulation` is the core entry
	# point for exactly that — and a player who commits an attempt and then walks away
	# from a fight would reach it. This is a PRECONDITION rather than a tidy-up:
	# `BodyRefusal` publishes "a refusal costs the actor nothing, because it happens
	# before any cost is paid", and here that stops depending on the gate being open.
	if active_attempt(actor) != null:
		return null
	# Face the tribulation owed for this path's next realm BEFORE validating anything
	# (ADR 0061), so R19-R30 are reachable by play rather than only by a test. Every
	# entry into an attempt runs through here — `start_attempt` and the one-shot
	# `try_breakthrough` — so the wave is charged once per committed attempt. The
	# return is discarded on purpose: a wave never opens the gate.
	Breakthrough.face_tribulation(actor, BodyPath.PATH_ID, rng)
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
	#
	# THE SEED IS DRAWN HERE AND STORED, never supplied by the caller and never
	# defaulted. `rng_state = 0 if rng == null else rng.seed` wrote the one seed whose
	# first draw (0.202272) sits BELOW every authored `chance_base` on the ladder, so
	# `randf() >= chance` never fired: every shipped attempt was a certain success and
	# the deviation loop could not run. A resolve that took a generator of its own made
	# it worse, because the roll then came off a stream the record never named. See
	# `BodyAttemptRoll`.
	var points: AcupointSet = actor.component(&"acupoints")
	committed.rng_state = BodyAttemptRoll.seed_for(rng)
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
##
## **NO GENERATOR, BY DESIGN.** The roll comes from the seed the commit stored, and
## nothing else — that is what makes an attempt that spans a save resolve to the
## outcome it was committed with. This used to accept one and prefer it, so a
## resolve took its draw off a stream the record never named: a caller could roll
## differently in the same session than the record claims, and the record was a lie
## about the trial it described. One door for randomness into a durable decision.
static func resolve_attempt(actor: Actor) -> bool:
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
	# Rebuilt from the record, never from a live stream: the roll and the huyệt a
	# deviation jams both come off this one generator, so a resolve after a reload
	# lands on the same body as a resolve without one.
	var generator := BodyAttemptRoll.replay(committed.rng_state)
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
	# ## DEF-0106: the path OWNS this decision, so the path earns the fate
	#
	# This `return true` is the decision that a breakthrough happened. `body_cultivation`
	# decides it, so it calls the facade here — the same rule `combat` follows at
	# `CombatDuel.record_defeat` and `character_creation_flow.gd` follows at
	# `grant_origin`. Fate is a write target, never a listener (ADR 0065).
	#
	# It sits on the GRANTED branch, after `try_advance_gated` has already said yes:
	# a refused advance returned three lines earlier, so nothing can earn a fate for a
	# breakthrough that never happened. It sits before `_end(actor, committed, true)`
	# so the fate's stat modifiers are re-projected onto a body whose realm has
	# already advanced, not onto the one it is leaving.
	earn_breakthrough_oath(actor)
	_end(actor, committed, true)
	return true


## Earn this path's breakthrough fate for `actor`, and VERIFY it. The one place the
## id, the source string and the verification live, so every body entry point pays
## identically — `try_breakthrough`, and the two-phase
## `BodyCultivationApi.begin_breakthrough` / `resolve_breakthrough` lifecycle, all of
## which arrive here through `resolve_attempt`.
##
## ## Why the verification IS the body
##
## `DestinyApi.earn_fate` returns the LEDGER, never a verdict, and every refusal
## path is byte-identical in shape — an unknown id, an already-held entry and a null
## actor all hand back the same unchanged ledger. Nothing is queued and nothing
## retries (ADR 0134), so a call trusted as an "already offered" silently never
## fires. `has_fate` afterwards is the only honest answer: the idiom
## `character_creation_flow.gd:280-284` takes and `event_prize.gd:95-96` does not.
##
## Nothing branches on the returned boolean — a breakthrough is not rolled back
## because its narrative receipt failed, and the refusal is an authoring bug rather
## than a player-facing outcome — but it makes the seam assertable without a test
## reaching into the ledger.
static func earn_breakthrough_oath(actor: Actor) -> bool:
	if actor == null:
		return false
	DestinyApi.earn_fate(actor, FATE_BARRIER, EARN_SOURCE)
	if DestinyApi.has_fate(actor, FATE_BARRIER):
		return true
	push_warning(
		(
			(
				"body_cultivation: a breakthrough was granted but %s was not earned (id unknown "
				+ "to the fate catalog?). Nothing records the debt and nothing retries it."
			)
			% String(FATE_BARRIER)
		)
	)
	return false


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


# --- Convenience -------------------------------------------------------------


## One-shot breakthrough: commit and resolve in a single call. This is the wired
## entry point, and it is the *same two calls* the two-phase lifecycle makes —
## there is no second implementation that can drift from the first.
##
## `busy` is held across both halves so a body cultivation action cannot
## interleave on the same huyệt set, and cleared on every exit.
##
## `rng` reaches `start_attempt` and stops there: the resolve reads the record, so
## the one press and the save-spanning attempt roll from the same seed by
## construction rather than by agreement.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null or points.busy:
		return false
	points.busy = true
	var committed := _start(actor, rng)
	if committed == null:
		points.busy = false
		return false
	var granted := resolve_attempt(actor)
	points.busy = false
	return granted


## Whether this actor's body plan permits a body breakthrough at all (ADR 0109).
##
## It is a PRECONDITION and never a modifier: it reads the gate and returns a
## boolean, and nothing here can widen a chance, lower a threshold, or skip a cost.
##
## An actor with no race takes no restriction. That is deliberate and unchanged: no
## body plan has been authored for it, and gating content on a content gap would lock
## a player out of a path nobody ever denied them (ADR 0109's boundary case).
static func _body_allows(actor: Actor) -> bool:
	if actor == null:
		return false
	if not RaceGate.path_unmet(actor, PathState.BODY).is_empty():
		return false
	return RaceGate.realm_ceiling_unmet(actor).is_empty()


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
