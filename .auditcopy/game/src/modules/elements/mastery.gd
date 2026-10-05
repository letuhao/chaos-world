class_name ElementMastery
extends RefCounted

## The elemental-mastery cultivation path (ADR 0004/0005/0006). It advances along the
## shared realm ladder; `stage_names` is its own vocabulary for display only.

const PATH_ID := &"elemental_mastery"
const MAX_ELEMENT_TIER := 3


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Elemental Mastery"
	def.stage_names = _stage_names()
	return def


static func max_tier(rank_id: StringName) -> int:
	var realm_tier := RealmDefaults.ladder().tier_of(rank_id)
	if realm_tier <= 0:
		return 1
	return mini(MAX_ELEMENT_TIER, realm_tier)


static func can_use(rules: ElementRules, rank_id: StringName, element_id: StringName) -> bool:
	var entry := rules.element(element_id)
	if entry == null:
		return false
	return entry.tier <= max_tier(rank_id)


static func _stage_names() -> Array[String]:
	return [
		"Spark",
		"Ember",
		"Kindling",
		"Blaze",
		"Attunement",
		"Resonance",
		"Channeling",
		"Confluence",
		"Convergence",
		"Elemental Sea",
		"Rising Tide",
		"Stormcall",
		"Maelstrom",
		"Elemental Avatar",
		"Lord of Elements",
		"King of Elements",
		"Emperor of Elements",
		"Sovereign of Elements",
		"Elemental Domain",
		"Elemental Law",
		"Elemental Edict",
		"Elemental Authority",
		"Elemental Hegemony",
		"Elemental Origin",
		"Primordial Element",
		"Dao of Elements",
		"Elemental Ascendant",
		"Elemental Transcendent",
		"Elemental Dao Ancestor",
		"Primordial Elemental Origin",
	]
