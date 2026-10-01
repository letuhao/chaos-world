class_name AscensionState
extends RefCounted

## Transcendent Ascension state (ADR 0021). Tracks ascension stage, dao comprehension,
## and unlocked abilities for the final tier (realms 28-30).

# Ascension stages
const STAGE_DAO_COMPREHENSION := 1
const STAGE_DAO_FUSION := 2
const STAGE_TRANSCENDENCE := 3

# Comprehension levels: Awakening → Understanding → Mastery → Fusion → Transcendence
const MAX_DAO_LEVEL := 5

var stage: int = STAGE_DAO_COMPREHENSION
var dao_type: StringName = &""
var dao_level: int = 1
var comprehension: float = 0.0
var abilities: Array[StringName] = []


func _init(
	p_stage: int = STAGE_DAO_COMPREHENSION,
	p_dao_type: StringName = &"",
	p_dao_level: int = 1,
	p_comprehension: float = 0.0
) -> void:
	stage = p_stage
	dao_type = p_dao_type
	dao_level = p_dao_level
	comprehension = p_comprehension


## Ascension is complete at stage 3 with dao_level 5.
func is_complete() -> bool:
	return stage >= STAGE_TRANSCENDENCE and dao_level >= MAX_DAO_LEVEL


## Advance to the next ascension stage (capped at 3).
func advance_stage() -> void:
	stage = mini(stage + 1, STAGE_TRANSCENDENCE)


## Improve dao comprehension level (clamped 1-5).
func improve_dao(amount: int) -> void:
	dao_level = clampi(dao_level + amount, 1, MAX_DAO_LEVEL)


## Add an unlocked ability (no duplicates).
func add_ability(ability_id: StringName) -> void:
	if not abilities.has(ability_id):
		abilities.append(ability_id)


func to_dict() -> Dictionary:
	return {
		"stage": stage,
		"dao_type": String(dao_type),
		"dao_level": dao_level,
		"comprehension": comprehension,
		"abilities": _string_array(abilities),
	}


static func from_dict(data: Dictionary) -> AscensionState:
	var state := AscensionState.new(
		int(data.get("stage", STAGE_DAO_COMPREHENSION)),
		StringName(data.get("dao_type", "")),
		int(data.get("dao_level", 1)),
		float(data.get("comprehension", 0.0))
	)
	for ability_id in data.get("abilities", []):
		state.abilities.append(StringName(ability_id))
	return state


func _string_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
