class_name MindAdvancement
extends RefCounted

## Mind-cultivation breakthrough (ADR 0013/0016/0024). Success empties the sea
## and grants the seed's rewards; failure is mental deviation — lost progress,
## sea turbulence, and a damaged channel.

const _ITEMS := preload("res://src/modules/items/api.gd")


## Preview the breakthrough conditions without consuming anything. Returns a
## dictionary with unmet conditions and costs.
static func preview(actor: Actor) -> Dictionary:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return {"ready": false, "conditions": ["No mind path"], "costs": {}}
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return {"ready": false, "conditions": ["Already at max realm"], "costs": {}}
	var seed := MindRealmSeed.for_realm(target.id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return {"ready": false, "conditions": ["Missing seed or sea"], "costs": {}}
	var conditions: Array[String] = []
	if state.progress < seed.progress_required:
		conditions.append("Progress: %d/%d" % [int(state.progress), int(seed.progress_required)])
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		conditions.append(
			(
				"Comprehension: %d/%d"
				% [int(actor.stats.derived(Stat.COMPREHENSION)), int(seed.comprehension_required)]
			)
		)
	if sea.turbulence > 0.0:
		conditions.append("Sea turbulent")
	if sea.clarity < seed.clarity_required:
		conditions.append("Clarity: %.2f/%.2f" % [sea.clarity, seed.clarity_required])
	if sea.purity < seed.purity_required:
		conditions.append("Purity: %.2f/%.2f" % [sea.purity, seed.purity_required])
	if sea.ratio(actor) < seed.sea_fill_required:
		conditions.append("Sea not full")
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		conditions.append("Missing breakthrough pill")
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or not channel.meets(seed.required_channel_state):
			conditions.append("Channel %s not ready" % id)
	if not Breakthrough.tier_gates_met(actor, target.index):
		conditions.append("Tier gates not met")
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + sea.clarity * 0.5, 0.05, 0.95
	)
	return {
		"ready": conditions.is_empty(),
		"conditions": conditions,
		"costs": {seed.breakthrough_item: 1},
		"chance": chance,
		"target": target.id,
	}


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
	sea.drain(actor, sea.current(actor))
	Breakthrough.try_advance(actor, MindPath.PATH_ID)
	MindTraining.synchronize(actor)
	# R19+: create the inside world anchor after breakthrough
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		_create_anchor(actor, target)
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD and actor.tribulation != null:
		actor.tribulation.apply_result(actor, true)
	actor.mark_stats_dirty()
	return true


static func _create_anchor(actor: Actor, target: RealmDef) -> void:
	# R19: create the seed world anchor
	if target.index == Breakthrough.IMMORTAL_REALM_THRESHOLD:
		if actor.inside_world == null:
			actor.inside_world = InsideWorld.new(InsideWorld.SEED)
		actor.inside_world.create_anchor()
	# R22: create the pocket world anchor
	elif target.index == Breakthrough.IMMORTAL_REALM_THRESHOLD + 3:
		if actor.inside_world != null and actor.inside_world.tier == InsideWorld.SEED:
			actor.inside_world.tier = InsideWorld.POCKET
			actor.inside_world.create_anchor()
	# R25: create the inner world anchor
	elif target.index == Breakthrough.IMMORTAL_REALM_THRESHOLD + 6:
		if actor.inside_world != null and actor.inside_world.tier == InsideWorld.POCKET:
			actor.inside_world.tier = InsideWorld.INNER
			actor.inside_world.create_anchor()


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
	sea.set_clarity(maxf(0.0, sea.clarity * 0.5))
	if not seed.required_meridians.is_empty():
		actor.meridians.damage_meridian(
			seed.required_meridians[_pick(rng, seed.required_meridians.size())]
		)
	actor.mark_stats_dirty()


static func _pick(rng: RandomNumberGenerator, count: int) -> int:
	if count <= 1:
		return 0
	return randi() % count if rng == null else rng.randi_range(0, count - 1)
