class_name QiAdvancement
extends RefCounted

## Qi-cultivation breakthrough (ADR 0011/0014/0024). Validates the realm seed,
## spends the pill, then rolls against breakthrough chance scaled by dantian
## quality. Failure is a qi deviation: lost progress, a scarred dantian, and a
## damaged channel.

const _ITEMS := preload("res://src/modules/items/api.gd")


static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var condition := QiBreakthroughCondition.new()
	if not Breakthrough.can_advance(actor, QiPath.PATH_ID, condition):
		return false
	var seed := QiRealmSeed.for_realm(target.id)
	var dantian := QiCultivationApi.dantian(actor)
	if seed == null or dantian == null:
		return false
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return false
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + dantian.quality * 0.5, 0.05, 0.95
	)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		_deviate(actor, state, seed, dantian, rng)
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# The dantian empties into the new realm and is re-sealed at its new capacity.
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.current = 0.0
	Breakthrough.try_advance(actor, QiPath.PATH_ID)
	QiTraining.synchronize(actor)
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	actor.mark_stats_dirty()
	return true


static func _deviate(
	actor: Actor, state: PathState, seed: QiRealmSeed, dantian: Dantian, rng: RandomNumberGenerator
) -> void:
	# Qi deviation scars the dantian and burns a channel it depended on.
	state.progress *= 0.5
	dantian.damage()
	dantian.set_quality(maxf(0.0, dantian.quality * 0.5))
	if not seed.required_meridians.is_empty():
		actor.meridians.damage_meridian(
			seed.required_meridians[_pick(rng, seed.required_meridians.size())]
		)
	actor.mark_stats_dirty()


static func _pick(rng: RandomNumberGenerator, count: int) -> int:
	if count <= 1:
		return 0
	return randi() % count if rng == null else rng.randi_range(0, count - 1)
