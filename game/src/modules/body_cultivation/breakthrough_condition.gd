class_name BodyBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")
## The foundation record's read (BL-0951): the wall lives in THIS condition, so the
## preview's unmet list and the enforced gate cannot disagree (ADR 0044).
const _FOUNDATION := preload("res://src/modules/foundation/api.gd")


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
	# BL-0951: the foundation wall. The carried foundation must clear the target seed's
	# authored floor; below it the refusal is NAMED, and because the preview renders this
	# same list, the wall is visible before it is hit (ADR 0044).
	if not seed.foundation_met(_FOUNDATION.foundation(actor)):
		unmet.append("foundation_insufficient")
	# Reported gate by gate, never as one omnibus line. A player told "tribulation,
	# inside world, ascension" cannot act on any of them: the tribulation is fought
	# somewhere else entirely, the inside world is grown by training, and the ascent
	# is walked step by step. One line naming three gates is the same defect as no
	# line at all, and it is why R19-R30 read as one unreachable wall.
	unmet.append_array(_tier_gate_unmet(actor, target.index))
	return unmet


## The tier gates that are shut for `target`, one clause each, in the order they
## are earned, and nothing at all when they are all open.
##
## Every verdict is core's own predicate, the same four `Breakthrough.tier_gates_met`
## ANDs, so this list cannot disagree with the gate it describes. The ASCENSION
## clause is core's wording too (`WorldAnchor.ascension_unmet`, ADR 0034): it names
## how many steps are left to walk, because a gate a player is told merely exists is
## a gate they cannot act on.
func _tier_gate_unmet(actor: Actor, target_index: int) -> Array[String]:
	var out: Array[String] = []
	# Below each gate's own threshold its predicate is true, so a mortal or spirit
	# realm sees none of this. Nothing here is conditional on the tier.
	if not Breakthrough.tribulation_ok(actor, target_index):
		out.append("Survive a tribulation fought for this realm")
	if not Breakthrough.inside_world_ok(actor, target_index):
		out.append("The realm inside you is not ready yet")
	if not Breakthrough.world_ok(actor, target_index):
		out.append("The world you made is not stable yet")
	if not Breakthrough.ascension_ok(actor, target_index):
		out.append(WorldAnchor.ascension_unmet(actor))
	return out


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
