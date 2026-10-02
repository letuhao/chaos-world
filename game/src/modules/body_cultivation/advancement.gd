class_name BodyAdvancement
extends RefCounted

const _ITEMS := preload("res://src/modules/items/api.gd")

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


## Preview the breakthrough without mutating anything. Returns a dictionary with:
##   - ready: bool — whether all conditions are met
##   - unmet: Array[String] — human-readable unmet conditions
##   - chance: float — evaluated breakthrough chance
##   - cost: StringName — breakthrough pill item id
##   - target: StringName — target realm id
static func preview(actor: Actor) -> Dictionary:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return {
			"ready": false, "unmet": ["No body path"], "chance": 0.0, "cost": &"", "target": &""
		}
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return {
			"ready": false,
			"unmet": ["Already at highest realm"],
			"chance": 0.0,
			"cost": &"",
			"target": &""
		}
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return {
			"ready": false, "unmet": ["No realm seed"], "chance": 0.0, "cost": &"", "target": &""
		}
	var condition := BodyBreakthroughCondition.new()
	var unmet: Array[String] = condition.describe_unmet(actor, state)
	var points: AcupointSet = actor.component(&"acupoints")
	return {
		"ready": unmet.is_empty(),
		"unmet": unmet,
		"chance": _chance(points, seed),
		"cost": seed.breakthrough_item,
		"target": target.id,
	}


## Start a breakthrough attempt. Validates all conditions, consumes the pill,
## and returns an attempt ID. Returns empty string when blocked.
## Only one active attempt is allowed at a time.
static func start_attempt(actor: Actor) -> StringName:
	if not actor.get_module_data(&"body_attempt").is_empty():
		return &""
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return &""
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return &""
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return &""
	var condition := BodyBreakthroughCondition.new()
	if not condition.can_breakthrough(actor, state, {}):
		return &""
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return &""
	var attempt := {
		"id": &"attempt_%d" % Time.get_ticks_msec(),
		"path_id": String(BodyPath.PATH_ID),
		"source": String(state.rank_id),
		"target": String(target.id),
		"pill": String(seed.breakthrough_item),
		"status": "pending",
	}
	actor.set_module_data(&"body_attempt", attempt)
	actor.mark_stats_dirty()
	return attempt.id


## Resolve a pending breakthrough attempt. Rolls chance, applies success/failure,
## and clears the attempt. Returns true on success.
static func resolve_attempt(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var attempt: Dictionary = actor.get_module_data(&"body_attempt")
	if attempt.is_empty() or attempt.get("status", "") != "pending":
		return false
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		actor.set_module_data(&"body_attempt", {})
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null or String(target.id) != attempt.get("target", ""):
		actor.set_module_data(&"body_attempt", {})
		return false
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		actor.set_module_data(&"body_attempt", {})
		return false
	var points: AcupointSet = actor.component(&"acupoints")
	var chance := _chance(points, seed)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		# Deviation: lose half the progress, jam a huyệt and tear the channel the
		# actor trained deepest, and cost integrity (ADR 0015/0023).
		state.progress *= 0.5
		var torn := _deepest_required_channel(actor, seed)
		_block_on_channel(points, torn, rng)
		if torn != &"":
			actor.meridians.damage_meridian(torn)
		actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)
		attempt["status"] = "failed"
		actor.set_module_data(&"body_attempt", {})
		actor.mark_stats_dirty()
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# Advance through the cumulative tier gate so no Immortal+/Transcendent+ gate
	# can be side-stepped. The module condition was validated before the pill was
	# consumed, so it is not re-checked here; re-running it would fail on the
	# already-consumed pill.
	var advanced := Breakthrough.try_advance_gated(actor, BodyPath.PATH_ID)
	# Drain the shared pool on success — the breakthrough consumes stored essence.
	if points != null:
		points.drain(seed.integrity_maximum)
	BodyTraining.synchronize(actor)
	# The milestone is NOT marked here. It is granted by training while in the
	# realm, so its physique bonus is earned rather than free (ADR 0023). It is
	# also self-consistent: the gate for the next realm demands refinement equal
	# to this realm's cap, which is only reachable by strengthening here.
	if target.index >= Tribulation.TRIBULATION_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	if advanced:
		# Entering a high tier *commits* the milestone it produces; the next tier
		# gates on it (ADR 0018-0021).
		WorldAnchor.commit(actor, target.index)
	attempt["status"] = "success" if advanced else "blocked"
	actor.set_module_data(&"body_attempt", {})
	actor.mark_stats_dirty()
	return advanced


static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null or points.busy:
		return false
	var condition := BodyBreakthroughCondition.new()
	if not Breakthrough.can_advance(actor, BodyPath.PATH_ID, condition):
		return false
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := BodyRealmSeed.for_realm(target.id)
	var chance := _chance(points, seed)
	points.busy = true
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		points.busy = false
		return false
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		# Deviation: lose half the progress, jam a huyệt and tear the channel the
		# actor trained deepest, and cost integrity (ADR 0015/0023). Both halves of
		# the wound land on the same meridian so the damage has a location.
		state.progress *= 0.5
		var torn := _deepest_required_channel(actor, seed)
		_block_on_channel(points, torn, rng)
		if torn != &"":
			actor.meridians.damage_meridian(torn)
		actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)
		actor.mark_stats_dirty()
		points.busy = false
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# Advance through the cumulative tier gate so no Immortal+/Transcendent+ gate
	# can be side-stepped. The module condition was validated before the pill was
	# consumed, so it is not re-checked here; re-running it would fail on the
	# already-consumed pill.
	var advanced := Breakthrough.try_advance_gated(actor, BodyPath.PATH_ID)
	# Drain the shared pool on success — the breakthrough consumes stored essence.
	points.drain(seed.integrity_maximum)
	BodyTraining.synchronize(actor)
	# The milestone is NOT marked here. It is granted by training while in the
	# realm, so its physique bonus is earned rather than free (ADR 0023). It is
	# also self-consistent: the gate for the next realm demands refinement equal
	# to this realm's cap, which is only reachable by strengthening here.
	if target.index >= Tribulation.TRIBULATION_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	if advanced:
		# Entering a high tier *commits* the milestone it produces; the next tier
		# gates on it (ADR 0018-0021).
		WorldAnchor.commit(actor, target.index)
	points.busy = false
	actor.mark_stats_dirty()
	return advanced


static func _block_random_open(points: AcupointSet, rng: RandomNumberGenerator) -> void:
	var open: Array[Acupoint] = []
	for point in points.points:
		if not point.blocked:
			open.append(point)
	if open.is_empty():
		return
	var index := (randi() % open.size()) if rng == null else rng.randi_range(0, open.size() - 1)
	open[index].block()


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


## The acupoint a deviation jams: one bound to the channel it tore, so the two
## halves of the wound sit on the same meridian.
static func _block_on_channel(
	points: AcupointSet, meridian_id: StringName, rng: RandomNumberGenerator
) -> void:
	if meridian_id != &"":
		var linked: Array[Acupoint] = []
		for point in points.points:
			if not point.blocked and AcupointDefaults.meridian_of(point.id) == meridian_id:
				linked.append(point)
		if not linked.is_empty():
			var index := randi() % linked.size()
			if rng != null:
				index = rng.randi_range(0, linked.size() - 1)
			linked[index].block()
			return
	_block_random_open(points, rng)
