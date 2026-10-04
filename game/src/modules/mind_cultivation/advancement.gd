class_name MindAdvancement
extends RefCounted

## Mind-cultivation breakthrough lifecycle (ADR 0013/0016/0024/0029).
##
## A breakthrough is transactional: `preview` reports the conditions and
## consumes nothing, `start` validates, spends the realm pill exactly once and
## commits a persisted `MindAttempt`, and `resolve_attempt` rolls that attempt
## into either an award or a recoverable deviation. Only one attempt is active
## per actor.
##
## `preview` and `start` AGREE, and that is a contract rather than a coincidence:
## a condition `preview` does not report is a button a screen offers that does
## nothing. `ready` is the boolean the mind screen binds its Breakthrough press
## to, so anything `start` refuses on — the attempt slot included — has to be a
## clause in `conditions` (BL-0152).
##
## The award is keyed on the attempt's identity (`outcome_granted`), not on the
## path's progress, so re-resolving one attempt can never grant twice. Success
## empties the sea and grants the target realm's awards once; failure is mental
## deviation — half the progress, sea turbulence, a damaged channel, same realm.
##
## `try_breakthrough` stays as the one-shot convenience wrapper over both steps.

const _ITEMS := preload("res://src/modules/items/api.gd")

## Module-owned attempt record. Core serializes it as raw data and this module
## rebuilds the typed attempt from it, so core never imports this class.
const ATTEMPT_KEY := &"mind_attempt"

## The evaluated chance's floor and ceiling, and the weight of the one input the
## roll is allowed to read. See `_chance`: excluding `Stat.BREAKTHROUGH_CHANCE`
## from that formula is this path's whole anti-certainty contract.
const MIN_CHANCE := 0.05
const MAX_CHANCE := 0.95
## Preparation quality: a fully sharpened sea is worth half the roll. Bounded by
## `MAX_CHANCE - MIN_CHANCE` because clarity is itself bounded, so the sum can
## never reach the clamp at any realm.
const CLARITY_TO_CHANCE := 0.5

## The fate a mind breakthrough earns (DEF-0106).
##
## `remembered_by_the_mountain`, chosen from the fate's OWN text: "Walked into a
## forbidden ridge and came back with the ridge's name in your mouth. Nobody has
## asked where you learned it. You have not offered." The mind path is the one that
## goes furthest past the limits of what it was given — a sea of consciousness
## sharpened until a channel holds a realm it had no business holding — so the
## returned knowledge nobody can account for IS what this path's success produces.
## Its `counters = [breakthroughs]` names a counter no shipped producer drives
## (DEF-0121), which is the second reason the fate rather than the counter is the
## honest earn here.
##
## It is also paid by `the_riven_peak_disaster.tres` and `the_returned_instrument
## .tres`; `earn_fate` is exactly-once, so those pay nothing twice (ADR 0065).
const FATE_BARRIER := &"remembered_by_the_mountain"

## The `source` string this path's earn carries, in the shape `QuestGrants
## .FATE_SOURCE_PREFIX + quest_id` and `EventDef.fate_source()` both build: it names
## the SYSTEM that earned the fate and the decision point, never the fate id itself
## (ADR 0065 on id namespaces).
const EARN_SOURCE := "mind_breakthrough"

# --- Read side ---------------------------------------------------------------

## The clause an attempt already in flight adds to `conditions`, published so a
## screen binds to the module's own wording instead of a copied string.
##
## `start` refuses a second attempt outright, so `preview` owes this clause. It
## used to report `ready: true` for an actor `start` would refuse, which put a
## READY label and a Breakthrough button that does nothing on the same screen
## (BL-0152). EVERY branch of `preview` reports it, because an early return that
## dropped it would reopen the same disagreement on a different actor.
const ATTEMPT_CLAUSE := "Attempt in flight"


## Preview the breakthrough conditions without consuming anything. Returns a
## dictionary with unmet conditions, costs, the evaluated chance, the target
## realm, and the active attempt id (empty when none is in flight).
static func preview(actor: Actor) -> Dictionary:
	var active := active_attempt(actor)
	# Collected up front and carried into every branch below, so neither clause
	# `start` refuses on can be the one a refusal path forgets. The order is
	# `start`'s own order: the ADR 0109 body gate is answered before the slot.
	var conditions: Array[String] = []
	conditions.append_array(_body_gate_unmet(actor))
	if active != null:
		conditions.append(ATTEMPT_CLAUSE)
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return _refusal(conditions, "No mind path", active)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return _refusal(conditions, "Already at max realm", active)
	var seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or source_seed == null or sea == null:
		return _refusal(conditions, "Missing seed or sea", active)
	# Entry checks the *source* realm's completed milestones; the target profile
	# supplies the pill and the progress bar (ADR 0024/0029).
	if state.progress < seed.progress_required:
		conditions.append("Progress: %d/%d" % [int(state.progress), int(seed.progress_required)])
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		conditions.append(
			(
				"Comprehension: %d/%d"
				% [int(actor.stats.derived(Stat.COMPREHENSION)), int(seed.comprehension_required)]
			)
		)
	if sea.turbulence > 0.0:
		conditions.append("Sea turbulent")
	if sea.clarity < source_seed.clarity_required:
		conditions.append("Clarity: %.2f/%.2f" % [sea.clarity, source_seed.clarity_required])
	if sea.purity < source_seed.purity_required:
		conditions.append("Purity: %.2f/%.2f" % [sea.purity, source_seed.purity_required])
	if sea.ratio(actor) < seed.sea_fill_required:
		conditions.append("Sea not full")
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		conditions.append("Missing breakthrough pill")
	for id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or not channel.meets(source_seed.required_channel_state):
			conditions.append("Channel %s not ready" % id)
	# The four shared tier gates and the anchor are SEPARATE clauses and all of them
	# are owed. ADR 0024 delegated the anchor to `MindAnchor` and nothing else, so
	# the shared list is reported here rather than assumed by the condition.
	var tier_unmet := _tier_gate_unmet(actor, target.index)
	var stage := MindAnchor.required_stage(target.index)
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		conditions.append_array(tier_unmet)
		if not MindAnchor.stage_met(actor, stage):
			# The shortfall, not the rule: a screen must be able to say which part of
			# the anchor is outstanding, and `MindAnchor.outstanding` reports exactly
			# the clause that is false for THIS actor.
			conditions.append(_anchor_reason(actor, stage))
	return {
		"ready": conditions.is_empty(),
		"conditions": conditions,
		# The shared gates on their own, so a screen can mark which of the four is
		# shut without re-deriving them out of the flat clause list above.
		"tier_gate_unmet": tier_unmet,
		"costs": {seed.breakthrough_item: 1},
		"chance": _chance(actor, sea),
		"target": target.id,
		"anchor_stage": stage,
		"attempt": _id(active),
		# The gate inputs this preview evaluated, so a caller can tell a genuinely
		# satisfied condition from one the screen has to go earn, and so a test can
		# prove the gate was satisfiable from a legal pre-state without re-deriving
		# the thresholds (ADR 0029).
		"gates": _gates(actor, state, seed, source_seed, sea, target),
	}


## The evaluated value and the threshold for every gate the entry rules apply,
## named by the same keys `preview` reports its unmet conditions under. The
## threshold is the seed's own authored value, so a screen or a test never has to
## restate it and cannot fall out of step with the gate it is describing.
static func _gates(
	actor: Actor,
	state: PathState,
	seed: MindRealmSeed,
	source_seed: MindRealmSeed,
	sea: SeaOfConsciousness,
	target: RealmDef
) -> Dictionary:
	var channels: Array[Dictionary] = []
	for id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		(
			channels
			. append(
				{
					"id": String(id),
					"required": String(source_seed.required_channel_state),
					"state": String(channel.state) if channel != null else "unknown",
					"met": channel != null and channel.meets(source_seed.required_channel_state),
				}
			)
		)
	var stage := MindAnchor.required_stage(target.index)
	return {
		"progress": {"value": state.progress, "required": seed.progress_required},
		"comprehension":
		{
			"value": actor.stats.derived(Stat.COMPREHENSION),
			"required": seed.comprehension_required,
		},
		"turbulence": {"value": sea.turbulence, "required": 0.0},
		# Clarity and purity are the SOURCE realm's milestones (ADR 0029): while
		# still standing in it, the sea caps at exactly these values.
		"clarity": {"value": sea.clarity, "required": source_seed.clarity_required},
		"purity": {"value": sea.purity, "required": source_seed.purity_required},
		"sea_fill": {"value": sea.ratio(actor), "required": seed.sea_fill_required},
		"pill": {"value": _ITEMS.has_item(actor, seed.breakthrough_item), "required": true},
		"channels": channels,
		"tribulation":
		{
			"required": target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD,
			"value": Breakthrough.tribulation_ok(actor, target.index),
		},
		# The three gates the anchor is NOT. They are published under the same keys
		# body publishes them under, each holding core's own verdict, so a screen can
		# mark which of the four is shut without restating a rule (ADR 0034).
		"inside_world":
		{
			"required": target.index > Breakthrough.IMMORTAL_REALM_THRESHOLD,
			"value": Breakthrough.inside_world_ok(actor, target.index),
		},
		"world":
		{
			"required": target.index > WorldAnchor.COMMIT_MICRO,
			"value": Breakthrough.world_ok(actor, target.index),
		},
		"ascent":
		{
			"required": target.index > WorldAnchor.COMMIT_MICRO,
			"value": Breakthrough.ascension_ok(actor, target.index),
			# Published as a PROGRESS, not a boolean: this gate is WALKED, four
			# deliberate steps, and a screen cannot render "four steps to walk" out
			# of a `false`.
			"outstanding": WorldAnchor.ascension_unmet(actor),
			"steps_remaining": actor.ascension.steps_remaining() if actor.ascension != null else 0,
		},
		"anchor":
		{
			"required": stage != MindAnchor.STAGE_NONE,
			"stage": String(stage),
			"value": MindAnchor.stage_met(actor, stage),
			# The named clause that is false right now, so a screen can mark the
			# actionable milestone without restating the stage policy.
			"outstanding": MindAnchor.outstanding(actor, stage),
		},
	}


## `MindAnchor.outstanding` names the shortfall, and never returns empty for a
## stage the caller already found unmet. The fallback keeps `conditions` free of a
## blank line if the two ever disagree.
static func _anchor_reason(actor: Actor, stage: StringName) -> String:
	var reason := MindAnchor.outstanding(actor, stage)
	return MindAnchor.describe_stage(stage) if reason == "" else reason


## A `preview` for an actor that cannot act at all: the conditions collected so
## far, plus the single reason there are no more to collect, and no costs or
## target because there is nothing to spend on. `attempt` is published here too,
## so a screen cannot read "nothing in flight" off a refusal that happens to have
## an attempt in flight.
static func _refusal(conditions: Array[String], reason: String, active: MindAttempt) -> Dictionary:
	var all := conditions.duplicate()
	all.append(reason)
	return {"ready": false, "conditions": all, "costs": {}, "attempt": _id(active)}


## The ADR 0109 clauses that are shut for this actor: a body plan that closes the
## mind path, and one whose `realm_ceiling` sits above the realm being entered.
##
## `_body_allows` refuses on exactly these, and `preview` owes them for the same
## reason it owes `ATTEMPT_CLAUSE`: three of the four authored races close the mind
## path outright, so without this a stoneborn actor read READY on the mind screen
## and its Breakthrough press did nothing. Core's own `label` is the clause, as in
## `_tier_gate_unmet`, and an empty list is the answer when both are open — which
## is every raceless actor, the boundary ADR 0109 deliberately leaves ungated.
static func _body_gate_unmet(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for entry in RaceGate.path_unmet(actor, PathState.MIND):
		out.append(String(entry.get("label", "")))
	for entry in RaceGate.realm_ceiling_unmet(actor):
		out.append(String(entry.get("label", "")))
	return out


## The shared tier gates that are shut for `target_index`, one clause each, in the
## order they are earned, and nothing at all when they are all open.
##
## Every verdict is core's own predicate — the same four `Breakthrough.tier_gates_met`
## ANDs — so this list cannot disagree with the gate that refuses. The ASCENSION
## clause is core's wording too (`WorldAnchor.ascension_unmet`, ADR 0034): it names
## how many steps are left to walk, because a gate a player is told merely exists is
## a gate they cannot act on.
##
## Below each gate's own threshold its predicate is true, so a mortal or spirit realm
## sees none of this. Nothing here is conditional on the tier, which is why it can be
## read at every boundary rather than only at a high one.
static func _tier_gate_unmet(actor: Actor, target_index: int) -> Array[String]:
	var out: Array[String] = []
	if not Breakthrough.tribulation_ok(actor, target_index):
		out.append("Survive a tribulation fought for this realm")
	if not Breakthrough.inside_world_ok(actor, target_index):
		out.append("The realm inside you is not ready yet")
	if not Breakthrough.world_ok(actor, target_index):
		out.append("The world you made is not stable yet")
	if not Breakthrough.ascension_ok(actor, target_index):
		out.append(WorldAnchor.ascension_unmet(actor))
	return out


## The evaluated chance, and the single formula that produces it.
##
## It reads the sea's clarity and NOTHING that the entry gate already pins. It
## deliberately does not read `Stat.BREAKTHROUGH_CHANCE`, exactly as
## `BodyAdvancement` does not (ADR 0028): core derives that stat as
## `0.1 + comprehension * 0.01 + will * 0.005`, and comprehension IS this path's
## entry gate. At attempt time the gate's own floor had therefore already carried
## the roll past the clamp — `comprehension_required` reaches 66 at R5, so
## `0.1 + 0.66 + 0.23` clipped to certainty and every one of the 25 transitions
## above R4 was a guaranteed success. `_deviate` and the ADR 0031 recovery item
## were unreachable content on 25 of the 29 boundaries.
##
## Clarity is bounded twice over, which is what makes this formula safe: the sea
## clamps it to 1.0, and `MindTraining.cultivate` caps it at the CURRENT realm's
## own `clarity_required`. Cultivating harder cannot buy a certain breakthrough;
## it buys a sharper sea, which is what the roll is supposed to read.
static func _chance(_actor: Actor, sea: SeaOfConsciousness) -> float:
	return clampf(MIN_CHANCE + sea.clarity * CLARITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)


# --- Attempt record ----------------------------------------------------------


## The stored attempt record, terminal or not, or null when there is none.
static func attempt(actor: Actor) -> MindAttempt:
	var stored: Variant = actor.get_module_data(ATTEMPT_KEY)
	if not stored is Dictionary or stored.is_empty():
		return null
	return MindAttempt.from_dict(stored)


## The attempt currently in flight, or null. One at a time, per actor.
static func active_attempt(actor: Actor) -> MindAttempt:
	var stored := attempt(actor)
	if stored == null or not stored.is_active():
		return null
	return stored


static func _store(actor: Actor, value: MindAttempt) -> void:
	actor.set_module_data(ATTEMPT_KEY, value.to_dict())


static func _id(value: MindAttempt) -> String:
	return "" if value == null else String(value.attempt_id)


# --- Start -------------------------------------------------------------------


## Commit a breakthrough attempt: validate, spend the realm pill exactly once,
## and persist the record. Returns null when refused — unprepared, no target
## realm, or another attempt is already active.
##
## **The body answers first (ADR 0109), and it answers HERE.** A body plan that
## closes the mind path, or one whose `realm_ceiling` sits above the realm being
## entered, is refused before any other check and before anything is spent. Two of
## the four authored races close mind outright, so this is the gate that actually
## bites — and it is here because this is the ONE call every mind entry point
## makes. `MindCultivationApi.try_breakthrough` reaches this by way of
## `try_breakthrough`, and `app/mind_cultivation_ui.gd` calls `try_breakthrough`
## DIRECTLY, skipping the facade altogether; a gate on the facade alone left the
## UI's Breakthrough button ungated, which is exactly how a stoneborn walked into
## mind cultivation. A rule a caller can walk around is not a rule. It is a
## precondition and never a modifier.
##
## One attempt at a time is the module's invariant, not an accident of the check
## order: `MindAttempt` is a single per-actor slot and `resolve_attempt` is
## idempotent because the award is keyed on that record's identity (ADR 0029). So
## a second `start` does not QUEUE or JOIN — it refuses, and `preview` reports it
## as `ATTEMPT_CLAUSE` rather than as ready. Returning the record already in
## flight instead would tell a caller a pill was spent when this call spent none.
static func start(actor: Actor, rng: RandomNumberGenerator = null) -> MindAttempt:
	if not _body_allows(actor):
		return null
	# Face the tribulation owed for this path's next realm BEFORE validating anything
	# (ADR 0061), so R19-R30 are reachable by play rather than only by a test. Both
	# entries into an attempt run through here — `start` itself and the one-shot
	# `try_breakthrough` — so the wave is charged once per committed attempt. The
	# return is discarded on purpose: a wave never opens the gate.
	Breakthrough.face_tribulation(actor, MindPath.PATH_ID, rng)
	if active_attempt(actor) != null:
		return null
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return null
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := MindRealmSeed.for_realm(target.id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return null
	if not Breakthrough.can_advance(actor, MindPath.PATH_ID, MindBreakthroughCondition.new()):
		return null
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return null
	var sequence := _next_sequence(actor)
	var committed := (
		MindAttempt
		. new(
			MindAttempt.make_id(actor.id, MindPath.PATH_ID, sequence),
			actor.id,
			MindPath.PATH_ID,
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
	committed.rng_state = 0 if rng == null else rng.seed
	committed.preparation = {
		"chance": _chance(actor, sea),
		"clarity": sea.clarity,
		"purity": sea.purity,
		"sea_ratio": sea.ratio(actor),
		"progress": state.progress,
		"pill": String(seed.breakthrough_item),
	}
	committed.commit()
	_store(actor, committed)
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
	var state := actor.path(MindPath.PATH_ID)
	# The attempt names its own target: the realm it is trying to enter, never
	# the one after it.
	var target := RealmDefaults.ladder().realm(committed.target_rank)
	if state == null or target == null or state.rank_id != committed.source_rank:
		# Something else moved this actor on, so the trial never ran.
		_end(actor, committed, false)
		return false
	var seed := MindRealmSeed.for_realm(committed.target_rank)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		_end(actor, committed, false)
		return false
	# The tier gates are re-read before the roll, so a gate that closed underneath
	# the attempt — a save round trip, a tribulation record that did not survive it —
	# costs no roll, no deviation and no award, and the attempt is CANCELLED rather
	# than failed. Body reads the gates here for the same reason; qi re-reads them at
	# the advance instead. This must stay ABOVE `mark_trial_complete`: below it the
	# record would read as a lost trial the actor never fought.
	if not Breakthrough.tier_gates_met(actor, target.index):
		_end(actor, committed, false)
		return false
	committed.mark_trial_complete()
	var generator := rng if rng != null else _replay(committed)
	var chance := float(committed.preparation.get("chance", _chance(actor, sea)))
	if generator.randf() >= chance:
		_deviate(actor, state, seed, sea, generator)
		_end(actor, committed, false)
		return false
	# The gate is the last thing that can still refuse, and a refusal must leave the
	# actor exactly as it was found: no realm, no rewards, no drained sea. The award
	# and the drain therefore both FOLLOW the advance, as they do on body and qi.
	# Draining first would hand the actor a full reservoir's worth of progress for a
	# breakthrough that never happened, and the drain is reachable precisely because
	# the advance can now refuse where `try_advance` never could.
	if not Breakthrough.try_advance_gated(actor, MindPath.PATH_ID):
		_end(actor, committed, false)
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	sea.drain(actor, sea.current(actor))
	MindTraining.synchronize(actor)
	# High tiers commit their anchor as an outcome of this breakthrough. Nothing here
	# decides a tribulation: the fight already paid its own award and consumed a dao
	# heart, so paying again here handed R19 twice the insight for one fight and
	# stacked two `heavenly_blessing` statuses (ADR 0041/0061). A breakthrough CONSUMES
	# a survivor; it does not manufacture one.
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		MindAnchor.commit(actor, target.index)
	# ## DEF-0106: the path OWNS this decision, so the path earns the fate
	#
	# This `return true` is the decision that a breakthrough happened, and
	# `mind_cultivation` is what decided it — so the facade is called HERE, not one
	# layer up. `app/mind_cultivation_ui.gd` calls `try_breakthrough` directly and
	# skips the facade entirely, so an earn placed on `MindCultivationApi` would be
	# an earn the Breakthrough button walks past. That is the same reason the ADR
	# 0109 gate lives at this layer and not above it, and the same rule
	# `combat` follows at `CombatDuel.record_defeat`: fate is a write target, never
	# a listener (ADR 0065).
	#
	# It sits on the GRANTED branch — a refused `try_advance_gated` returned four
	# lines above — and before `_end(actor, committed, true)`, so the fate's
	# modifiers are projected onto a mind that has already entered the realm.
	#
	# `earn_fate` returns the LEDGER, never a verdict, and every refusal path is
	# byte-identical in shape and queues nothing (ADR 0134) — so the earn is
	# VERIFIED with `has_fate` rather than trusted, which is what
	# `character_creation_flow.gd:280-284` does and `event_prize.gd:95-96` does not.
	DestinyApi.earn_fate(actor, FATE_BARRIER, EARN_SOURCE)
	if not DestinyApi.has_fate(actor, FATE_BARRIER):
		push_warning(
			(
				(
					"mind_cultivation: a breakthrough was granted but %s was not earned (id unknown "
					+ "to the fate catalog?). Nothing records the debt and nothing retries it."
				)
				% String(FATE_BARRIER)
			)
		)
	_end(actor, committed, true)
	return true


## End the attempt and persist the record. `granted` sets the once-only outcome
## flag; a `cancelled` attempt ends without one, because no trial ran.
static func _end(actor: Actor, committed: MindAttempt, granted: bool) -> void:
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


## The seed the attempt committed to, so a persisted attempt resolves to the same
## outcome after a reload instead of rerolling.
static func _replay(committed: MindAttempt) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = committed.rng_state
	return generator


# --- Convenience -------------------------------------------------------------


## One-shot breakthrough: commit and resolve in a single call. Prefer
## `start`/`resolve_attempt` when the attempt may span a save or a UI turn.
##
## This is an entry point in its own right, not a convenience over a gated one:
## `app/mind_cultivation_ui.gd` calls it directly, so the ADR 0109 gate has to be
## read at or below it rather than at the facade this call happens to bypass.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	if start(actor, rng) == null:
		return false
	return resolve_attempt(actor, rng)


## Whether this actor's body plan permits a mind breakthrough at all (ADR 0109).
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
	if not RaceGate.path_unmet(actor, PathState.MIND).is_empty():
		return false
	return RaceGate.realm_ceiling_unmet(actor).is_empty()


static func _deviate(
	actor: Actor,
	state: PathState,
	seed: MindRealmSeed,
	sea: SeaOfConsciousness,
	rng: RandomNumberGenerator
) -> void:
	# Mental deviation clouds the sea and burns a channel it depended on.
	state.progress *= 0.5
	sea.add_turbulence(0.5)
	sea.set_clarity(maxf(0.0, sea.clarity * 0.5))
	if not seed.required_meridians.is_empty():
		actor.meridians.damage_meridian(
			seed.required_meridians[_pick(rng, seed.required_meridians.size())]
		)
	actor.mark_stats_dirty()


static func _pick(rng: RandomNumberGenerator, count: int) -> int:
	if count <= 1:
		return 0
	return randi() % count if rng == null else rng.randi_range(0, count - 1)
