class_name BodyBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	return describe_unmet(actor, state).is_empty()


## Return a list of human-readable unmet condition strings. Empty when ready.
## Used by the preview to show the player what they need to do.
func describe_unmet(actor: Actor, state: PathState) -> Array[String]:
	if state.path_id != BodyPath.PATH_ID:
		return ["Not on the body cultivation path"]
	var ladder := RealmDefaults.ladder()
	var target := ladder.next(state.rank_id)
	if target == null:
		return ["Already at the highest realm"]
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return ["No realm seed for target"]
	var unmet: Array[String] = []
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	if integrity == null:
		unmet.append("Body integrity pool missing")
	elif integrity.ratio() < 1.0:
		unmet.append("Body integrity not full")
	if state.progress < seed.progress_required:
		unmet.append("Progress %d/%d" % [int(state.progress), int(seed.progress_required)])
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		unmet.append(
			(
				"Physique %d/%d"
				% [int(actor.stats.get_base(Stat.PHYSIQUE)), int(seed.physique_required)]
			)
		)
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		unmet.append("Missing breakthrough pill")
	if not _acupoints_ready(actor, seed, ladder.index_of(state.rank_id)):
		unmet.append("Acupoints not ready (full pool + quality)")
	if not _meridians_and_tribulation_ready(actor, seed, target):
		unmet.append("Meridians or tier gates not met")
	return unmet


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
	# The shared pool must be full — all acupoints read the same reservoir.
	if not acupoint_set.is_full():
		return false
	for definition in AcupointDefaults.definitions():
		if definition.unlock_index > realm_index:
			continue
		var point: Acupoint = null
		for p in acupoint_set.points:
			if p.id == definition.id:
				point = p
				break
		if point == null or point.quality < seed.quality_required:
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
