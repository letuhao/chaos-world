class_name BodyAdvancement
extends RefCounted

const _ITEMS := preload("res://src/modules/items/api.gd")


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
	for point in points.points:
		point.current = 0.0
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
