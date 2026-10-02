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

# --- Read side ---------------------------------------------------------------


## Preview the breakthrough conditions without consuming anything. Returns a
## dictionary with unmet conditions, costs, the evaluated chance, the target
## realm, and the active attempt id (empty when none is in flight).
static func preview(actor: Actor) -> Dictionary:
	var active := active_attempt(actor)
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return {"ready": false, "conditions": ["No mind path"], "costs": {}, "attempt": _id(active)}
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return {
			"ready": false,
			"conditions": ["Already at max realm"],
			"costs": {},
			"attempt": _id(active),
		}
	var seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or source_seed == null or sea == null:
		return {
			"ready": false,
			"conditions": ["Missing seed or sea"],
			"costs": {},
			"attempt": _id(active),
		}
	# Entry checks the *source* realm's completed milestones; the target profile
	# supplies the pill and the progress bar (ADR 0024/0029).
	var conditions: Array[String] = []
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
	var stage := MindAnchor.required_stage(target.index)
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		if not Breakthrough.tribulation_ok(actor, target.index):
			conditions.append("Tribulation not survived")
		if not MindAnchor.stage_met(actor, stage):
			conditions.append(MindAnchor.describe_stage(stage))
	return {
		"ready": conditions.is_empty(),
		"conditions": conditions,
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
		"anchor":
		{
			"required": stage != MindAnchor.STAGE_NONE,
			"stage": String(stage),
			"value": MindAnchor.stage_met(actor, stage),
		},
	}


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
static func start(actor: Actor, rng: RandomNumberGenerator = null) -> MindAttempt:
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
	committed.mark_trial_complete()
	var generator := rng if rng != null else _replay(committed)
	var chance := float(committed.preparation.get("chance", _chance(actor, sea)))
	if generator.randf() >= chance:
		_deviate(actor, state, seed, sea, generator)
		_end(actor, committed, false)
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	sea.drain(actor, sea.current(actor))
	if not Breakthrough.try_advance(actor, MindPath.PATH_ID):
		_end(actor, committed, false)
		return false
	MindTraining.synchronize(actor)
	# High tiers commit their anchor as an outcome of this breakthrough, and the
	# survived tribulation is spent here (ADR 0024/0029).
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		if actor.tribulation != null:
			actor.tribulation.apply_result(actor, true)
		MindAnchor.commit(actor, target.index)
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
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	if start(actor, rng) == null:
		return false
	return resolve_attempt(actor, rng)


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
