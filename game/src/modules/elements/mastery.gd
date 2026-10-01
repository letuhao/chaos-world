class_name ElementMastery
extends RefCounted

## The elemental-mastery cultivation path (ADR 0003/0004). Ranks gate element tiers.

const PATH_ID := &"elemental_mastery"
const RANKS := [&"awakened", &"attuned", &"adept", &"master", &"grandmaster", &"sovereign"]
const MAX_TIER_BY_RANK := [1, 1, 2, 2, 3, 3]


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Elemental Mastery"
	def.ranks = _ranks()
	return def


static func rank_index(rank_id: StringName) -> int:
	return RANKS.find(rank_id)


static func max_tier(rank_id: StringName) -> int:
	var index := rank_index(rank_id)
	if index < 0:
		return 1
	return int(MAX_TIER_BY_RANK[index])


static func _ranks() -> Array[StringName]:
	var out: Array[StringName] = []
	for rank in RANKS:
		out.append(rank)
	return out
