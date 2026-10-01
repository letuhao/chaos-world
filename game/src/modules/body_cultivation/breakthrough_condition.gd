class_name BodyBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != BodyPath.PATH_ID:
		return false
	var ladder := RealmDefaults.ladder()
	var target := ladder.next(state.rank_id)
	if target == null:
		return false
	var seed := BodyRealmSeed.for_realm(target.id)
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	if seed == null or integrity == null or integrity.ratio() < 1.0:
		return false
	if not _basic_requirements_met(actor, state, seed):
		return false
	if not _acupoints_ready(actor, seed, ladder.index_of(state.rank_id)):
		return false
	return _meridians_and_tribulation_ready(actor, seed, target)


func _basic_requirements_met(actor: Actor, state: PathState, seed: BodyRealmSeed) -> bool:
	if state.progress < seed.progress_required:
		return false
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		return false
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		return false
	return true


func _acupoints_ready(actor: Actor, seed: BodyRealmSeed, realm_index: int) -> bool:
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	if acupoint_set == null:
		return false
	var points := {}
	for point in acupoint_set.points:
		points[point.id] = point
	for definition in AcupointDefaults.definitions():
		if definition.unlock_index > realm_index:
			continue
		var point: Acupoint = points.get(definition.id)
		if point == null or not point.is_full() or point.quality < seed.quality_required:
			return false
	return true


func _meridians_and_tribulation_ready(actor: Actor, seed: BodyRealmSeed, target: RealmDef) -> bool:
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or channel.state != &"strengthened":
			return false
		if channel.refinement < seed.required_refinement:
			return false
	# Immortal+ additionally needs survived tribulation, a stable inside world,
	# and at Transcendent a stable world plus completed ascension (ADR 0018-0021).
	return Breakthrough.tier_gates_met(actor, target.index)


func describe() -> String:
	return "Full healthy acupoints and integrity, trained channels, progress, physique, and realm pill"
