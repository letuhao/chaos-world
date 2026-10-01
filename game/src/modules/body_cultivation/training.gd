class_name BodyTraining
extends RefCounted

const _ITEMS := preload("res://src/modules/items/api.gd")


static func synchronize(actor: Actor) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	if acupoint_set != null:
		acupoint_set.synchronize(state.rank_id, actor.meridians.get_capacity_bonus())
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	if seed != null and integrity != null:
		integrity.set_maximum(seed.integrity_maximum)
	actor.mark_stats_dirty()


static func cultivate(actor: Actor, amount: float) -> bool:
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	if acupoint_set == null or acupoint_set.busy or amount <= 0.0 or not is_finite(amount):
		return false
	var state := actor.path(BodyPath.PATH_ID)
	if state == null or acupoint_set.open_count() == 0:
		return false
	synchronize(actor)
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	var energy := amount * realm.power * (1.0 + actor.meridians.get_flow_bonus())
	var share := energy / acupoint_set.open_count()
	for point in acupoint_set.points:
		if not point.blocked:
			point.fill(share)
			point.quality = minf(seed.quality_target, point.quality + share / point.capacity * 0.01)
	state.progress += energy
	actor.change_resource(BodyStats.BODY_INTEGRITY, energy * 0.1)
	actor.mark_stats_dirty()
	return true


static func strengthen(actor: Actor, meridian_id: StringName) -> bool:
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	var state := actor.path(BodyPath.PATH_ID)
	if acupoint_set == null or acupoint_set.busy or state == null:
		return false
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	# Unlock anything the current realm grants before looking the channel up, so
	# the first strengthen on a newly-available meridian is not rejected.
	actor.meridians.unlock_for_realm(state.rank_id)
	var channel := actor.meridians.get_meridian(meridian_id)
	if seed == null or channel == null:
		return false
	var cap_reached := (
		channel.state == &"strengthened" and channel.refinement >= seed.refinement_cap
	)
	if cap_reached and not _needs_point_training(acupoint_set, meridian_id, seed.quality_target):
		return false
	acupoint_set.busy = true
	if not _ITEMS.consume_item(actor, seed.strengthening_item):
		acupoint_set.busy = false
		return false
	match channel.state:
		&"closed":
			actor.meridians.open_meridian(meridian_id)
		&"open":
			actor.meridians.expand_meridian(meridian_id)
		&"expanded":
			actor.meridians.strengthen_meridian(meridian_id)
		&"strengthened":
			actor.meridians.refine_meridian(meridian_id, seed.refinement_cap)
		&"damaged":
			actor.meridians.repair_meridian(meridian_id)
	_train_points(acupoint_set, meridian_id, seed.quality_target)
	synchronize(actor)
	acupoint_set.busy = false
	return true


static func _needs_point_training(
	points: AcupointSet, channel_id: StringName, target: float
) -> bool:
	for definition in AcupointDefaults.definitions():
		if definition.meridian_id != channel_id:
			continue
		for point in points.points:
			if point.id == definition.id and (point.blocked or point.quality < target):
				return true
	return false


static func _train_points(points: AcupointSet, channel_id: StringName, target: float) -> void:
	for definition in AcupointDefaults.definitions():
		if definition.meridian_id != channel_id:
			continue
		for point in points.points:
			if point.id == definition.id:
				point.clear_block()
				point.quality = maxf(point.quality, minf(target, point.quality + 0.02))
