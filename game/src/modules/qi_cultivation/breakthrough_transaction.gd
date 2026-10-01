class_name QiBreakthroughTransaction
extends RefCounted

## Breakthrough transaction for Qi Cultivation (ADR 0011/0014/0024).
## Implements preview and execution with atomic cost policy.
##
## Preview returns structured unmet conditions and costs without consuming
## anything. Execution validates all conditions, consumes the pill, and
## rolls for success/failure. On failure, applies deviation consequences.

const _ITEMS := preload("res://src/modules/items/api.gd")


## Preview the breakthrough. Returns a dictionary with:
## - can_attempt: bool
## - target_realm: String
## - unmet_conditions: Array[String]
## - costs: Dictionary
## - chance: float (0.0-1.0)
static func preview(actor: Actor) -> Dictionary:
	var result := {
		"can_attempt": false,
		"target_realm": "",
		"unmet_conditions": [],
		"costs": {},
		"chance": 0.0,
	}
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		result["unmet_conditions"].append("no_qi_path")
		return result
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		result["unmet_conditions"].append("max_realm_reached")
		return result
	result["target_realm"] = target.id
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		result["unmet_conditions"].append("no_seed_for_target")
		return result
	var dantian := QiCultivationApi.dantian(actor)
	if dantian == null:
		result["unmet_conditions"].append("no_dantian")
		return result

	# Check all conditions
	if state.progress < seed.progress_required:
		result["unmet_conditions"].append("insufficient_progress")
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		result["unmet_conditions"].append("insufficient_comprehension")
	if dantian.quality < seed.dantian_quality_required:
		result["unmet_conditions"].append("insufficient_quality")
	if dantian.ratio(actor) < seed.dantian_fill_required:
		result["unmet_conditions"].append("dantian_not_full")
	if dantian.injured:
		result["unmet_conditions"].append("dantian_injured")
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		result["unmet_conditions"].append("missing_breakthrough_item")
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null or not channel.meets(seed.required_channel_state):
			result["unmet_conditions"].append("channel_not_ready:%s" % meridian_id)
	# Tier gates
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		if actor.tribulation == null or not actor.tribulation.is_complete():
			result["unmet_conditions"].append("tribulation_not_complete")
		if actor.inside_world == null or not actor.inside_world.is_stable():
			result["unmet_conditions"].append("inside_world_not_stable")
	if target.index >= Breakthrough.TRANSCENDENT_REALM_THRESHOLD:
		if actor.world == null or not actor.world.is_stable():
			result["unmet_conditions"].append("world_not_stable")
		if actor.ascension == null or not actor.ascension.is_complete():
			result["unmet_conditions"].append("ascension_not_complete")

	# Calculate chance
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + dantian.quality * 0.5, 0.05, 0.95
	)
	result["chance"] = chance
	result["can_attempt"] = result["unmet_conditions"].is_empty()
	result["costs"] = {
		"breakthrough_item": seed.breakthrough_item,
	}
	return result


## Execute the breakthrough. Returns true on success, false on failure.
## On failure, applies deviation consequences (progress loss, dantian damage,
## channel damage). The pill is consumed regardless of outcome.
static func execute(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var seed := QiRealmSeed.for_realm(target.id)
	var dantian := QiCultivationApi.dantian(actor)
	if seed == null or dantian == null:
		return false
	# Consume the pill
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return false
	# Roll for success
	var chance := clampf(
		actor.stats.derived(Stat.BREAKTHROUGH_CHANCE) + dantian.quality * 0.5, 0.05, 0.95
	)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		_deviate(actor, state, seed, dantian, rng)
		return false
	# Success: grant rewards and advance
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


## Attempt to cancel a committed breakthrough. This counts as a failed attempt
## with disclosed recoverable consequences. It cannot refund/reroll into a free
## second attempt.
static func cancel(actor: Actor) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var seed := QiRealmSeed.for_realm(target.id)
	var dantian := QiCultivationApi.dantian(actor)
	if seed == null or dantian == null:
		return false
	_deviate(actor, state, seed, dantian, null)
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
