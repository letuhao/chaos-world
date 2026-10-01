class_name MindAdvancement
extends RefCounted

## Mind-cultivation breakthrough (ADR 0013/0016/0024). Success empties the sea
## and grants the seed's rewards; failure is mental deviation — lost progress,
## sea turbulence, and a damaged channel.

const _ITEMS := preload("res://src/modules/items/api.gd")


static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var condition := MindBreakthroughCondition.new()
	if not Breakthrough.can_advance(actor, MindPath.PATH_ID, condition):
		return false
	var seed := MindRealmSeed.for_realm(target.id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return false
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return false
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + sea.clarity * 0.5, 0.05, 0.95
	)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		_deviate(actor, state, seed, sea, rng)
		return false
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	sea.current = 0.0
	Breakthrough.try_advance(actor, MindPath.PATH_ID)
	MindTraining.synchronize(actor)
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	actor.mark_stats_dirty()
	return true


static func _deviate(
	actor: Actor,
	state: PathState,
	seed: MindRealmSeed,
	sea: SeaOfConsciousness,
	rng: RandomNumberGenerator
) -> void:
	# Mental deviation clouds the sea and burns a channel it depended on.
	state.progress *= 0.5
	sea.add_turbulence(0.5)
	sea.clarity = maxf(0.0, sea.clarity * 0.5)
	if not seed.required_meridians.is_empty():
		actor.meridians.damage_meridian(
			seed.required_meridians[_pick(rng, seed.required_meridians.size())]
		)
	actor.mark_stats_dirty()


static func _pick(rng: RandomNumberGenerator, count: int) -> int:
	if count <= 1:
		return 0
	return randi() % count if rng == null else rng.randi_range(0, count - 1)
