class_name MindTraining
extends RefCounted

## Mind-cultivation action layer (ADR 0013/0016/0024): fill the sea of
## consciousness, meditate to calm turbulence, and train a meridian.

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
	sea.capacity = seed.sea_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	sea.tier = seed.sea_tier
	sea.current = clampf(sea.current, 0.0, sea.capacity)
	actor.mark_stats_dirty()


static func cultivate(actor: Actor, amount: float) -> bool:
	var sea := MindCultivationApi.sea(actor)
	var state := actor.path(MindPath.PATH_ID)
	if sea == null or state == null or amount <= 0.0 or not is_finite(amount):
		return false
	if sea.is_full():
		return false
	synchronize(actor)
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	var gain := amount * realm.power * (1.0 + actor.meridians.get_flow_bonus())
	sea.fill(gain)
	# Deep meditation sharpens clarity up to the seed's requirement.
	sea.clarity = minf(seed.clarity_required, sea.clarity + gain / 1000.0)
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
	match channel.state:
		MeridianState.CLOSED:
			actor.meridians.open_meridian(meridian_id)
		MeridianState.OPEN:
			actor.meridians.expand_meridian(meridian_id)
		MeridianState.EXPANDED:
			actor.meridians.strengthen_meridian(meridian_id)
		MeridianState.DAMAGED:
			actor.meridians.repair_meridian(meridian_id)
		_:
			actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap)
	synchronize(actor)
	return true
