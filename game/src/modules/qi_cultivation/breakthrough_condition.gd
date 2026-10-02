class_name QiBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != QiPath.PATH_ID:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := QiRealmSeed.for_realm(target.id) if target != null else null
	var dantian := QiCultivationApi.dantian(actor)
	if seed == null or dantian == null:
		return false
	return (
		_dantian_ready(actor, state, seed, dantian)
		and _ITEMS.has_item(actor, seed.breakthrough_item)
		and _channels_ready(actor, seed)
		# Immortal+ adds tribulation, a stable inside world, and at Transcendent a
		# stable world plus completed ascension (ADR 0018-0021).
		and Breakthrough.tier_gates_met(actor, target.index)
	)


func _dantian_ready(actor: Actor, state: PathState, seed: QiRealmSeed, dantian: Dantian) -> bool:
	# A scar must be healed before the attempt, not merely refilled. `damage`
	# drops usable capacity to 75% and clamps the reservoir down with it, so an
	# injured dantian refills to a full ratio again and would otherwise sail
	# through the fill gate on a structurally compromised core. The realm's
	# `recovery_item` is what closes the wound (ADR 0031).
	if dantian.injured:
		return false
	if state.progress < seed.progress_required:
		return false
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		return false
	if dantian.quality < seed.dantian_quality_required:
		return false
	return dantian.ratio(actor) >= seed.dantian_fill_required


func describe() -> String:
	return "Dantian filled and refined, channels trained, comprehension, and realm pill"


func _channels_ready(actor: Actor, seed: QiRealmSeed) -> bool:
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or not channel.meets(seed.required_channel_state):
			return false
	return true
