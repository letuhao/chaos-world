class_name LootEncounterDef
extends Resource

## An authored domain encounter: which bosses it hosts and in which order, at
## which authored tiers, and which loot table each boss drops from at each tier.
##
## `domain_id` is the back-reference the content audit checks against
## `res://data/domains/<domain_id>.tres`, and `boss_ids` must be listed in that
## domain's `boss_ids` so the two directions agree.
##
## `key_reach` is the entry gate (ADR 0033): the highest domain tier this
## encounter opens. A key item's numeric `key_reach` property decides whether the
## actor may enter. 0 means the domain needs no key at all.

@export var id: StringName = &""
@export var display_name: String = ""
@export var domain_id: StringName = &""
## Defeat order. The next boss spawns as soon as the previous one is defeated,
## independently of whether its reward has been picked up.
@export var boss_ids: Array[StringName] = []
@export var tiers: Array[LootTier] = []
@export var key_reach: int = 0


func tier_at(tier_index: int) -> LootTier:
	for candidate in tiers:
		if candidate != null and candidate.tier == tier_index:
			return candidate
	return null


func tier_count() -> int:
	return tiers.size()


func highest_tier() -> int:
	var best := -1
	for candidate in tiers:
		if candidate != null:
			best = maxi(best, candidate.tier)
	return best


## One primitive descriptor per authored tier, for the UI and for tests.
func tier_views() -> Array:
	var out: Array = []
	for candidate in tiers:
		if candidate == null:
			continue
		(
			out
			. append(
				{
					"tier": candidate.tier,
					"label": candidate.label,
					"realm": String(candidate.realm),
					"rarity": String(candidate.rarity),
					"vitality": candidate.vitality,
					"boss_count": candidate.boss_ids().size(),
				}
			)
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["tier"]) < int(b["tier"])
	)
	return out
