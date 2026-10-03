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
		acupoint_set.synchronize(state.rank_id)
		var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
		if integrity != null:
			acupoint_set.set_pool(integrity)
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	if seed != null and integrity != null:
		integrity.set_maximum(seed.integrity_maximum)
		# Realms 19-30 reinforce the same meridian network instead of opening new
		# channels; the authored resonance rank is what makes that progression
		# curve visible (ADR 0017/0028). Never lowers a rank the actor has earned.
		actor.meridians.set_resonance_rank(
			maxi(actor.meridians.resonance_rank, seed.resonance_rank)
		)
	actor.mark_stats_dirty()


## Meditate to raise comprehension (insight source for realm entry floors).
## Returns true when comprehension was raised. The amount scales with the
## actor's insight_gain stat and the current realm's throughput factor.
static func meditate(actor: Actor, amount: float) -> bool:
	if amount <= 0.0 or not is_finite(amount):
		return false
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return false
	var insight_gain := actor.stats.derived(Stat.INSIGHT_GAIN)
	var gain := amount * insight_gain
	var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	actor.stats.set_base(Stat.COMPREHENSION, comprehension + gain)
	actor.mark_stats_dirty()
	return true


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
	# One unit of training work is worth the realm's RATE, and only the rate: this
	# is a bounded per-realm number that says how much this realm's training
	# counts, never how strong a thing from this realm is. See `realm_profile.gd`
	# for why those are different numbers. `BodyTraining.meditate` deliberately
	# does not read it — comprehension is earned from the insight-gain stat, so
	# body and qi cannot drift apart on two different ladders.
	var energy := (
		amount * BodyRealmProfile.factor(state.rank_id) * (1.0 + actor.meridians.get_flow_bonus())
	)
	# Fill the shared body_integrity pool, not per-acupoint storage.
	acupoint_set.fill(energy)
	# Raise quality toward the seed target for all open points. The target is a
	# ceiling for this realm, not a reset: a point already trained above it (a
	# fresh point starts at 0.5, and strengthening only ever adds) must not be
	# dragged back down, or cultivation would silently undo real training.
	for point in acupoint_set.points:
		if not point.blocked:
			point.quality = maxf(
				point.quality, minf(seed.quality_target, point.quality + energy * 0.001)
			)
	state.progress += energy
	actor.mark_stats_dirty()
	return true


## Undo the recoverable overlay a failed breakthrough left behind: repair one
## injured channel and clear the blockages on its linked acupoints. Consumes the
## realm's recovery item. This is the only action that clears a blockage, so
## every realm must author a `recovery_item` (ADR 0015/0023).
##
## A blockage is cleared even when `meridian_id` names a meridian the actor has
## NOT unlocked, and nothing else changes in that case. That case is a migration
## path, not a route: `BodyAdvancement` will not jam a huyệt whose meridian is
## off the network, so the shipped failure branch cannot produce one. What it can
## produce is an actor carrying one — a save written before that rule, whose
## `blocked` flag travelled through `Acupoint.from_dict` untouched. Refusing
## there leaves that actor with no route to the next realm at all, which is the
## one outcome this action exists to prevent, so it frees the huyệt and still
## charges the item.
##
## All-or-nothing: nothing is mutated unless the item is present and consumed.
## Returns true when the recovery actually changed something.
static func recover(actor: Actor, meridian_id: StringName) -> bool:
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	var state := actor.path(BodyPath.PATH_ID)
	if acupoint_set == null or acupoint_set.busy or state == null:
		return false
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.recovery_item == &"":
		return false
	actor.meridians.unlock_for_realm(state.rank_id)
	var channel := actor.meridians.get_meridian(meridian_id)
	# Decide first, mutate second: a meridian with nothing to repair must not
	# consume the item, and a failed consume must leave the blockage in place.
	var linked: Array[Acupoint] = []
	for point in acupoint_set.points:
		if point.blocked and AcupointDefaults.meridian_of(point.id) == meridian_id:
			linked.append(point)
	var injured := channel != null and channel.is_injured()
	if not injured and linked.is_empty():
		return false
	if not _ITEMS.consume_item(actor, seed.recovery_item):
		return false
	acupoint_set.busy = true
	if injured:
		actor.meridians.repair_meridian(meridian_id)
	for point in linked:
		point.clear_block()
	synchronize(actor)
	acupoint_set.busy = false
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
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	else:
		match channel.state:
			&"closed":
				actor.meridians.open_meridian(meridian_id)
			&"open":
				actor.meridians.expand_meridian(meridian_id)
			&"expanded":
				actor.meridians.strengthen_meridian(meridian_id)
			&"strengthened":
				actor.meridians.refine_meridian(meridian_id, seed.refinement_cap)
	_train_points(acupoint_set, meridian_id, seed.quality_target)
	synchronize(actor)
	acupoint_set.busy = false
	# Training while in this realm completes its milestone, which pays a one-time
	# physique bonus. Marking on entry instead would make the bonus free.
	var progress: BodyProgress = actor.component(&"body_progress")
	if progress != null:
		progress.mark_complete(actor, seed)
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
