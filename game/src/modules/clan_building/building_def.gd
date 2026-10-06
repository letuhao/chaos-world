class_name BuildingDef
extends Resource

## One authored building definition (ADR 0126).
##
## A building is a clan infrastructure node that grants non-combat bonuses and
## unlocks verbs. It never directly modifies combat stats (ADR 0064's
## "recognition, never power" rule). Buildings are constructed with materials
## (earned through hunting/combat) and contribution (earned through standing).
##
## ## Yin-yang: every advantage carries its counterpart
##
## Each building costs contribution per day in upkeep. Unpaid upkeep for 3 days
## makes the building inactive. After 30 days unpaid, the building loses a level.
## Overextension (total_building_levels > clan_level * 3) halves all bonuses.
## Rival sabotage can destroy a level, prevented by Defensive Works.

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice.
@export var description: String = ""

## The building category: lineage, combat, economy, cultivation, or military.
@export var category: StringName = &""

## Maximum level this building can reach (1-3).
@export var max_level: int = 3

## Base material cost for level 1. Materials come from hunting/combat only.
@export var base_cost_materials: int = 100
## Base contribution cost for level 1. Contribution comes from standing.
@export var base_cost_contribution: int = 50
## Cost multiplier per level: cost = base_cost * cost_scale^(level-1).
@export var cost_scale: float = 2.0
## Base upkeep per day at level 1. Upkeep = base_upkeep * level.
@export var base_upkeep: int = 10
## Clan level required to construct this building.
@export var unlock_clan_level: int = 1

## Bonuses granted at each level. Array of Dictionaries with keys:
## `stat_id`, `value`, `is_percent`. Index 0 = level 1, index 1 = level 2, etc.
@export var bonuses: Array[Dictionary] = []
## Verbs unlocked at each level. Array of Array[StringName].
## Index 0 = level 1 verbs, index 1 = level 2 verbs, etc.
@export var verbs_unlocked: Array = []
## Tags for categorization and filtering.
@export var tags: Array[StringName] = []


## The material cost for `level` (1-indexed).
func material_cost(level: int) -> int:
	return int(float(base_cost_materials) * pow(cost_scale, level - 1))


## The contribution cost for `level` (1-indexed).
func contribution_cost(level: int) -> int:
	return int(float(base_cost_contribution) * pow(cost_scale, level - 1))


## The upkeep per day at `level`.
func upkeep_at(level: int) -> int:
	return base_upkeep * level


## The construction time in hours for `level`.
func construction_hours(level: int) -> int:
	match level:
		1:
			return 1
		2:
			return 2
		3:
			return 4
	return 0


## The bonuses granted at `level` (1-indexed). Empty if level exceeds authored bonuses.
func bonuses_at(level: int) -> Array[Dictionary]:
	if level < 1 or level > bonuses.size():
		return []
	var result: Array[Dictionary] = []
	var entry = bonuses[level - 1]
	if entry is Dictionary:
		result.append(entry)
	elif entry is Array:
		for b in entry:
			if b is Dictionary:
				result.append(b)
	return result


## The verbs unlocked at `level` (1-indexed).
func verbs_at(level: int) -> Array[StringName]:
	if level < 1 or level > verbs_unlocked.size():
		return []
	var out: Array[StringName] = []
	for v in verbs_unlocked[level - 1]:
		out.append(StringName(v))
	return out


## Whether this building can be constructed at `level` (1-indexed).
func can_build_at(level: int) -> bool:
	return level >= 1 and level <= max_level


## The rank discount factor for a given rank. Head 25%, Heir 15%, Core 10%, Inner 5%, Outer 0%.
static func rank_discount(rank: StringName) -> float:
	match rank:
		&"head":
			return 0.25
		&"heir":
			return 0.15
		&"core":
			return 0.10
		&"inner":
			return 0.05
		&"outer":
			return 0.0
	return 0.0
