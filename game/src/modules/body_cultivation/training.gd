class_name BodyTraining
extends RefCounted

const _ITEMS := preload("res://src/modules/items/api.gd")
## The sitting's time price and the final band's cliff (BL-0951): every press below spends
## the body's life through the foundation facade, like every other module edge.
const _FOUNDATION := preload("res://src/modules/foundation/api.gd")


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
	# BL-0951: the sitting costs the body's life, and the final band has no sittings left.
	if _FOUNDATION.training_refusal(actor) != "":
		return false
	_FOUNDATION.spend_periods(actor, _FOUNDATION.TRAINING_PRESS_PERIODS)
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
	# BL-0951: the sitting costs the body's life, and the final band has no sittings left.
	if _FOUNDATION.training_refusal(actor) != "":
		return false
	_FOUNDATION.spend_periods(actor, _FOUNDATION.TRAINING_PRESS_PERIODS)
	# One unit of training work is worth the realm's RATE, and only the rate: this
	# is a bounded per-realm number that says how much this realm's training
	# counts, never how strong a thing from this realm is. See
	# `core/realm_rate.gd` for why those are different numbers.
	# `BodyTraining.meditate` deliberately does not read it — comprehension is
	# earned from the insight-gain stat, so body and qi cannot drift apart on two
	# different ladders.
	var energy := (
		amount * RealmRate.factor(state.rank_id) * (1.0 + actor.meridians.get_flow_bonus())
	)
	# The place's density and the actor's own rate: one shared call, so a body
	# cultivator cannot miss a factor a qi cultivator gets (ADR 0214, ADR 0926).
	energy = CultivationGain.scale_gain(actor, energy)
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


## Train one channel toward this realm's cap, paying the realm's
## `strengthening_item` — OR, when the channel is burned, hand the burn to
## `recover` and pay the realm's `recovery_item` instead (ADR 0141).
##
## A BURNED CHANNEL IS NOT TRAINED, IT IS REPAIRED, AND THE REPAIR HAS ITS OWN
## PRICE. Every realm authors both roles: `strengthening_item` walks the ladder,
## `recovery_item` undoes what a deviation left behind, which is the torn channel
## AND the huyệt jammed on it (ADR 0031). Charging the channel elixir for the
## repair left `recover` — and `recover_next`, the facade verb added for exactly
## this wound — with no route a player could afford, so the authored third role
## was demanded by nothing and the missing verb went unnoticed: a torn channel
## WAS repairable through the facade, just by spending the wrong item.
##
## Delegated rather than reimplemented, so there is one repair at one price: a
## second copy of the consume here is exactly how the two prices drifted apart
## the first time. `recover`'s all-or-nothing rule comes with it, and so does the
## blockage the same deviation jammed on this channel — the old injury branch
## repaired the channel and left the jam standing.
##
## The cost of delegating, stated rather than hidden: the repair press no longer
## trains the huyệt bound to this channel and no longer marks the realm's training
## milestone. A repair is not a training step. The very next press on the
## now-healthy channel does both, and the wound itself was `recover`'s to close.
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
	# Ahead of the consume: a burn has its own price (ADR 0141).
	if channel.is_injured():
		return recover(actor, meridian_id)
	# BL-0951: the final band has no sittings left — a refusal, and refusals cost nothing.
	# The injury branch above stays open: repair is healing, not training.
	if _FOUNDATION.training_refusal(actor) != "":
		return false
	if (
		at_channel_cap(channel, seed)
		and not needs_point_training(acupoint_set, meridian_id, seed.quality_target)
	):
		return false
	acupoint_set.busy = true
	if not _ITEMS.consume_item(actor, seed.strengthening_item):
		acupoint_set.busy = false
		return false
	# BL-0951: the sitting costs the body's life. Spent AFTER the consume, because a
	# missing elixir is a refusal and refusals cost nothing (ADR 0044).
	_FOUNDATION.spend_periods(actor, _FOUNDATION.TRAINING_PRESS_PERIODS)
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


## The channels `strengthen_next` would offer, in the order it offers them: the ones
## this realm introduces, then the ones the next realm requires. Deduplicated,
## because a seed's `channel_training` and `required_meridians` name the same
## channels at most realms and a walk that visits each twice buys nothing.
##
## ONE DEFINITION, TWO READERS: the facade walks this to train, and
## `BodyRefusal.strengthen_unavailable` asks the same list which candidate would
## refuse. Two lists would let the screen report a cause the verb never hit, which is
## worse than the unnamed `false` this replaced (ADR 0150). Empty when there is
## nothing to train: no body path, or no authored seed.
static func strengthen_candidates(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var state := actor.path(BodyPath.PATH_ID) if actor != null else null
	if state == null:
		return out
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return out
	for meridian_id in seed.channel_training:
		if not out.has(meridian_id):
			out.append(meridian_id)
	for meridian_id in seed.required_meridians:
		if not out.has(meridian_id):
			out.append(meridian_id)
	return out


static func at_channel_cap(channel: MeridianState, seed: BodyRealmSeed) -> bool:
	# A channel at its refinement ceiling has nothing left to gain from training.
	# Named because the answer is a RULE the realm seed and the channel state
	# jointly decide, not an inline comparison: `strengthen` asks it, and the
	# tests ask it, so one definition is the only place that can be wrong.
	return channel.state == &"strengthened" and channel.refinement >= seed.refinement_cap


## Whether this channel's huyệt still have training left in them. A channel at its
## refinement cap can still be worth a press while one of its huyệt is jammed or
## below `target`, so this is the other half of the cap question — and it is public
## because `BodyRefusal` asks the same question to name a refusal, rather than
## re-implementing it and being wrong in a second direction.
static func needs_point_training(
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
