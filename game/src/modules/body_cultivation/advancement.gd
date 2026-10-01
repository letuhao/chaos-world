class_name BodyAdvancement
extends RefCounted

const _ITEMS := preload("res://src/modules/items/api.gd")


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
	var avg_quality := 0.0 if points == null else points.average_quality()
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + avg_quality * 0.5, 0.05, 0.95
	)
	return {
		"ready": unmet.is_empty(),
		"unmet": unmet,
		"chance": chance,
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
		actor.set_component(&"body_attempt", null)
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null or String(target.id) != attempt.get("target", ""):
		actor.set_component(&"body_attempt", null)
		return false
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		actor.set_component(&"body_attempt", null)
		return false
	var points: AcupointSet = actor.component(&"acupoints")
	var avg_quality := 0.0 if points == null else points.average_quality()
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + avg_quality * 0.5, 0.05, 0.95
	)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		# Deviation: lose half the progress, block an open acupoint, and damage a
		# required channel (ADR 0015/0023).
		state.progress *= 0.5
		_block_random_open(points, rng)
		if not seed.required_meridians.is_empty():
			actor.meridians.damage_meridian(seed.required_meridians[0])
		actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)
		attempt["status"] = "failed"
		actor.set_module_data(&"body_attempt", {})
		actor.mark_stats_dirty()
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# Drain the shared pool on success — the breakthrough consumes stored essence.
	if points != null:
		points.drain(seed.integrity_maximum)
	Breakthrough.try_advance(actor, BodyPath.PATH_ID)
	BodyTraining.synchronize(actor)
	if target.index >= Tribulation.TRIBULATION_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	attempt["status"] = "success"
	actor.set_module_data(&"body_attempt", {})
	actor.mark_stats_dirty()
	return true


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
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + points.average_quality() * 0.5, 0.05, 0.95
	)
	points.busy = true
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		points.busy = false
		return false
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		# Deviation: lose half the progress, block an open acupoint, and damage a
		# required channel (ADR 0015/0023).
		state.progress *= 0.5
		_block_random_open(points, rng)
		if not seed.required_meridians.is_empty():
			actor.meridians.damage_meridian(seed.required_meridians[0])
		actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)
		actor.mark_stats_dirty()
		points.busy = false
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# Drain the shared pool on success — the breakthrough consumes stored essence.
	points.drain(seed.integrity_maximum)
	Breakthrough.try_advance(actor, BodyPath.PATH_ID)
	BodyTraining.synchronize(actor)
	if target.index >= Tribulation.TRIBULATION_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	points.busy = false
	actor.mark_stats_dirty()
	return true


static func _block_random_open(points: AcupointSet, rng: RandomNumberGenerator) -> void:
	var open: Array[Acupoint] = []
	for point in points.points:
		if not point.blocked:
			open.append(point)
	if open.is_empty():
		return
	var index := (randi() % open.size()) if rng == null else rng.randi_range(0, open.size() - 1)
	open[index].block()
