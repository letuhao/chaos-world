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
	# The shared reservoir must reach the realm's authored charge target U(R),
	# not 100%. `integrity_target` was authored for exactly this and was dead
	# while the gate hardcoded a full pool.
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	var target_ratio := seed.integrity_target
	if integrity == null:
		unmet.append("Body integrity pool missing")
	elif integrity.ratio() < target_ratio:
		unmet.append(
			"Body integrity %.0f%%/%d%%" % [integrity.ratio() * 100.0, int(target_ratio * 100.0)]
		)
	if state.progress < seed.progress_required:
		unmet.append("Progress %d/%d" % [int(state.progress), int(seed.progress_required)])
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		unmet.append(
			(
				"Physique %d/%d"
				% [int(actor.stats.get_base(Stat.PHYSIQUE)), int(seed.physique_required)]
			)
		)
	# Insight floor: comprehension raised by meditation, never bought (ADR 0023).
	if actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required:
		(
			unmet
			. append(
				(
					"Comprehension %d/%d"
					% [
						int(actor.stats.get_base(Stat.COMPREHENSION)),
						int(seed.insight_required),
					]
				)
			)
		)
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		unmet.append("Missing breakthrough pill")
	# Acupoints own quality and blockage only. Pool fullness is reported once,
	# above, so an empty reservoir no longer also reads as "acupoints not ready".
	if not _acupoints_ready(actor, seed, ladder.index_of(state.rank_id)):
		unmet.append("Acupoint quality below the realm requirement")
	var wounded := _wounded_channels(actor, seed)
	if not wounded.is_empty():
		unmet.append("Damaged channels need repair: %s" % ", ".join(wounded))
	if not _channels_ready(actor, seed):
		unmet.append("Required channels are not trained deep enough")
	# Reported independently of the channels: a wound must not hide a closed
	# Immortal+ gate, or the player repairs the body and hits the same wall.
	if not Breakthrough.tier_gates_met(actor, target.index):
		unmet.append("Immortal tier gates not met (tribulation, inside world, ascension)")
	return unmet


## Quality of every acupoint the current realm has unlocked. Pool fullness is a
## separate, single gate (`describe_unmet`), so this check stays about quality.
func _acupoints_ready(actor: Actor, seed: BodyRealmSeed, realm_index: int) -> bool:
	var acupoint_set: AcupointSet = actor.component(&"acupoints")
	if acupoint_set == null:
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


## An injured required channel halves its own bonuses (ADR 0017) but must still
## be repaired before the next attempt: pushing forward wounded would make the
## penalty permanent and free. Returns the names of the wounds it found.
func _wounded_channels(actor: Actor, seed: BodyRealmSeed) -> Array[String]:
	var wounded: Array[String] = []
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel != null and channel.is_injured():
			wounded.append(String(id))
	return wounded


## Structural channel requirement: present, strengthened, and deep enough.
## Injury is deliberately NOT checked here: `_wounded_channels` reports it on its
## own line, and folding it in again would make one wound read as two unmet
## conditions. The wound still blocks, via that message being non-empty.
func _channels_ready(actor: Actor, seed: BodyRealmSeed) -> bool:
	for id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or channel.state != MeridianState.STRENGTHENED:
			return false
		if channel.refinement < seed.required_refinement:
			return false
	return true


func describe() -> String:
	return (
		"Full body integrity, acupoint quality, trained channels, progress, physique, "
		+ "comprehension, and the realm pill"
	)
