class_name QiBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")
## The qi climb's element gate reads the elements FACADE and nothing else: the mastery
## channel lives there, and a bare class reference from this module would be a second
## door into it (the same reason `_ITEMS` is a facade preload).
const _ELEMENTS := preload("res://src/modules/elements/api.gd")


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != QiPath.PATH_ID:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	var seed := QiRealmSeed.for_realm(target.id) if target != null else null
	var dantian := QiAccess.dantian(actor)
	if seed == null or dantian == null:
		return false
	return (
		_dantian_ready(actor, state, seed, dantian)
		and _ITEMS.has_item(actor, seed.breakthrough_item)
		and _channels_ready(actor, seed)
		and _elements_ready(actor, seed)
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
	return (
		"Dantian filled and refined, channels trained to the realm's depth, comprehension,"
		+ " the realm's element mastery, and realm pill"
	)


## Present, at the realm's state, and refined to the realm's depth. The whole
## predicate is `QiRealmSeed.channel_met`, so this gate, `QiAdvancement.preview`
## and `QiBreakthroughTransaction.preview` cannot disagree (ADR 0044) — the three
## each carried their own copy, which is exactly how a preview came to report a
## realm enterable while the transaction refused it.
func _channels_ready(actor: Actor, seed: QiRealmSeed) -> bool:
	for id in seed.required_meridians:
		if not seed.channel_met(actor.meridians.get_meridian(id)):
			return false
	return true


## ADR 0004's "master elements to rise": the target realm's authored element gate,
## satisfied by the actor's TOTAL element mastery (every element summed). The
## comparison is `QiRealmSeed.element_mastery_met`, so this gate and the transaction's
## preview cannot disagree (ADR 0044) — the same rule `channel_met` follows. The
## mastery is read through the elements facade; this module never touches its stats.
func _elements_ready(actor: Actor, seed: QiRealmSeed) -> bool:
	return seed.element_mastery_met(_ELEMENTS.total_mastery(actor))
