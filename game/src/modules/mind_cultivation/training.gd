class_name MindTraining
extends RefCounted

## Mind-cultivation action layer (ADR 0013/0016/0024): fill the sea of
## consciousness, meditate to calm turbulence, train a meridian, and strengthen
## the sea's structure with its catalyst.

const _ITEMS := preload("res://src/modules/items/api.gd")


static func synchronize(actor: Actor) -> void:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	var seed := MindRealmSeed.for_realm(state.rank_id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return
	sea.set_structural_capacity(seed.sea_capacity * (1.0 + actor.meridians.get_capacity_bonus()))
	sea.set_tier(seed.sea_tier)
	var pool := actor.resource(MindStats.MIND_POWER)
	if pool != null:
		pool.set_maximum(sea.structural_capacity)
		sea.drain(actor, sea.current(actor))
		sea.fill(actor, pool.current)
	actor.mark_stats_dirty()


static func cultivate(actor: Actor, amount: float) -> bool:
	var sea := MindCultivationApi.sea(actor)
	var state := actor.path(MindPath.PATH_ID)
	if sea == null or state == null or amount <= 0.0 or not is_finite(amount):
		return false
	if sea.is_full(actor):
		return false
	synchronize(actor)
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	var gain := amount * realm.power * (1.0 + actor.meridians.get_flow_bonus())
	sea.fill(actor, gain)
	# Deep meditation sharpens clarity and purity toward the seed's targets.
	sea.set_clarity(minf(seed.clarity_required, sea.clarity + gain / 1000.0))
	sea.set_purity(minf(seed.purity_required, sea.purity + gain / 1200.0))
	state.progress += gain
	actor.mark_stats_dirty()
	return true


## Calm turbulence. This is the mind system's unique recovery (ADR 0016).
static func meditate(actor: Actor, amount: float) -> bool:
	var sea := MindCultivationApi.sea(actor)
	if sea == null or amount <= 0.0 or not is_finite(amount):
		return false
	if sea.turbulence <= 0.0:
		return false
	sea.calm(amount)
	actor.mark_stats_dirty()
	return true


static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or not _ITEMS.has_item(actor, seed.training_item):
		return false
	if not _ITEMS.consume_item(actor, seed.training_item):
		return false
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	else:
		match channel.state:
			MeridianState.CLOSED:
				actor.meridians.open_meridian(meridian_id)
			MeridianState.OPEN:
				actor.meridians.expand_meridian(meridian_id)
			MeridianState.EXPANDED:
				actor.meridians.strengthen_meridian(meridian_id)
			_:
				actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap)
	synchronize(actor)
	return true


## Strengthen the sea's structure with the realm's sea catalyst. This is the
## Thức Hải milestone: it raises clarity and purity to the realm's targets.
static func strengthen_sea(actor: Actor) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.sea_catalyst.is_empty():
		return false
	if not _ITEMS.has_item(actor, seed.sea_catalyst):
		return false
	if not _ITEMS.consume_item(actor, seed.sea_catalyst):
		return false
	var sea := MindCultivationApi.sea(actor)
	if sea == null:
		return false
	sea.set_clarity(maxf(sea.clarity, seed.clarity_required))
	sea.set_purity(maxf(sea.purity, seed.purity_required))
	sea.trained_stage = maxi(sea.trained_stage, 1)
	synchronize(actor)
	return true
