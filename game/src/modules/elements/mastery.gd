class_name ElementMastery
extends RefCounted

## The elemental-mastery cultivation path (ADR 0004). It advances along the shared
## realm ladder (ADR 0005); realm tier gates which element tiers are usable.

const PATH_ID := &"elemental_mastery"
const MAX_ELEMENT_TIER := 3


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Elemental Mastery"
	return def


static func max_tier(rank_id: StringName) -> int:
	var realm_tier := RealmDefaults.ladder().tier_of(rank_id)
	if realm_tier <= 0:
		return 1
	return mini(MAX_ELEMENT_TIER, realm_tier)
