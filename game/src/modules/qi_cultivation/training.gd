class_name QiTraining
extends RefCounted

## Qi-cultivation action layer (ADR 0011/0014/0024): refine the dantian by
## circulating qi, and train a meridian with the realm's elixir.

const _ITEMS := preload("res://src/modules/items/api.gd")


static func synchronize(actor: Actor) -> void:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	var seed := QiRealmSeed.for_realm(state.rank_id)
	var dantian := QiCultivationApi.dantian(actor)
	if seed == null or dantian == null:
		return
	# Capacity comes from the seed, scaled by the meridian network's capacity
	# bonus so channel investment visibly widens the dantian.
	dantian.set_structural_capacity(
		seed.dantian_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	)
	dantian.set_tier(seed.dantian_tier)
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.set_maximum(dantian.effective_capacity())
	actor.mark_stats_dirty()


static func cultivate(actor: Actor, amount: float) -> bool:
	var dantian := QiCultivationApi.dantian(actor)
	var state := actor.path(QiPath.PATH_ID)
	if dantian == null or state == null or amount <= 0.0 or not is_finite(amount):
		return false
	if dantian.is_full(actor):
		return false
	synchronize(actor)
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	# Meridian flow bonus speeds circulation; realm power scales the gain.
	var gain := amount * realm.power * (1.0 + actor.meridians.get_flow_bonus())
	dantian.fill(actor, gain)
	# Circulating qi refines the dantian toward the seed's quality target.
	dantian.set_quality(minf(seed.dantian_quality_required, dantian.quality + gain / 1000.0))
	state.progress += gain
	actor.mark_stats_dirty()
	return true


static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or _ITEMS.has_item(actor, seed.training_item) == false:
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
				# Already strengthened: the elixir deepens it toward the seed cap.
				actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap)
	synchronize(actor)
	return true
