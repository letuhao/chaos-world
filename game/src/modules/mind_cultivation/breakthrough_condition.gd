class_name MindBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != MindPath.PATH_ID:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := MindRealmSeed.for_realm(target.id) if target != null else null
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return false
	return (
		_sea_ready(actor, state, seed, sea)
		and _ITEMS.has_item(actor, seed.breakthrough_item)
		and _channels_ready(actor, seed)
		and _anchor_ready(actor, target)
		and Breakthrough.tier_gates_met(actor, target.index)
	)


func _sea_ready(
	actor: Actor, state: PathState, seed: MindRealmSeed, sea: SeaOfConsciousness
) -> bool:
	if state.progress < seed.progress_required:
		return false
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		return false
	# A turbulent sea must be calmed by meditation before the attempt (ADR 0016).
	if sea.turbulence > 0.0 or sea.clarity < seed.clarity_required:
		return false
	if sea.purity < seed.purity_required:
		return false
	return sea.ratio(actor) >= seed.sea_fill_required


func describe() -> String:
	return "Sea filled and clear, channels strengthened, comprehension, and realm pill"


func _channels_ready(actor: Actor, seed: MindRealmSeed) -> bool:
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or not channel.meets(seed.required_channel_state):
			return false
	return true


func _anchor_ready(actor: Actor, target: RealmDef) -> bool:
	# R19+ requires a stable inside world with anchor
	if target.index >= Breakthrough.IMMORTAL_REALM_THRESHOLD:
		var inside_world := actor.inside_world
		if inside_world == null or not inside_world.is_stable():
			return false
		if not inside_world.anchor_created or not inside_world.anchor_trial_passed:
			return false
	# R28+ requires a stable world
	if target.index >= Breakthrough.TRANSCENDENT_REALM_THRESHOLD:
		var world := actor.world
		if world == null or not world.is_stable():
			return false
	return true
