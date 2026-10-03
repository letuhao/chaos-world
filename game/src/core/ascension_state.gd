class_name AscensionState
extends RefCounted

## Transcendent Ascension state (ADR 0021). The ascent is *walked*, not written:
## `steps` is the count of the ritual and `is_complete` reads it, so a hand-set
## `stage`/`dao_level` cannot open the gate the walk opens (ADR 0058).

# Ascension stages
const STAGE_DAO_COMPREHENSION := 1
const STAGE_DAO_FUSION := 2
const STAGE_TRANSCENDENCE := 3

# Comprehension levels: Awakening → Understanding → Mastery → Fusion → Transcendence
const MAX_DAO_LEVEL := 5

## Steps the ascent takes to carry stage 1/dao 1 to the caps. Four, because stage 2
## is one step of understanding, stage 3 is two steps of fusion, and dao 5 needs
## one more: every step is a strict increase over the last, so no step is free.
const ASCENT_STEPS := 4

## What one step of the ascent is worth in comprehension. The ritual's price is
## deliberate: an ascent that only counts steps is a counter, and one that only
## counts comprehension is a bar. Both are read, so neither alone opens the gate.
const STEP_COMPREHENSION := 100.0

## The comprehension a whole walked ascent leaves behind. Derived from the two
## constants above rather than authored beside them, so retuning a step cannot
## leave the total describing a walk that no longer happens.
const REQUIRED_COMPREHENSION := float(ASCENT_STEPS) * STEP_COMPREHENSION

var stage: int = STAGE_DAO_COMPREHENSION
var dao_type: StringName = &""
var dao_level: int = 1
var comprehension: float = 0.0
## How many steps of the ascent this state has walked. The gate reads this, never
## `stage`, so writing the caps by hand leaves the ascent unfinished.
var steps: int = 0
var abilities: Array[StringName] = []


func _init(
	p_stage: int = STAGE_DAO_COMPREHENSION,
	p_dao_type: StringName = &"",
	p_dao_level: int = 1,
	p_comprehension: float = 0.0,
	p_steps: int = 0
) -> void:
	stage = p_stage
	dao_type = p_dao_type
	dao_level = p_dao_level
	comprehension = p_comprehension
	steps = maxi(0, p_steps)


## Ascension is complete at stage 3 with dao_level 5 — reached by *walking* the
## whole ladder, which is what `steps` and its comprehension attest. `advance_stage`
## and `improve_dao` still move the caps, so the walk cannot be short-circuited by
## calling them; they only pay for a step the ritual also has to take.
func is_complete() -> bool:
	return (
		stage >= STAGE_TRANSCENDENCE
		and dao_level >= MAX_DAO_LEVEL
		and steps >= ASCENT_STEPS
		and comprehension >= REQUIRED_COMPREHENSION
	)


## Walk one step of the ascent: one stage and one dao level, plus this step's share
## of comprehension. Refused at the top, so a `while ascend(actor)` terminates on
## the state rather than on a caller-supplied bound.
func ascend() -> bool:
	if steps >= ASCENT_STEPS:
		return false
	steps += 1
	stage = mini(stage + 1, STAGE_TRANSCENDENCE)
	dao_level = clampi(dao_level + 1, 1, MAX_DAO_LEVEL)
	comprehension += STEP_COMPREHENSION
	return true


## Steps of the ascent still to walk. Zero when the ascent is finished.
func steps_remaining() -> int:
	return maxi(0, ASCENT_STEPS - steps)


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
		"steps": steps,
		"abilities": _string_array(abilities),
	}


static func from_dict(data: Dictionary) -> AscensionState:
	var comprehension := float(data.get("comprehension", 0.0))
	var state := AscensionState.new(
		int(data.get("stage", STAGE_DAO_COMPREHENSION)),
		StringName(data.get("dao_type", "")),
		int(data.get("dao_level", 1)),
		comprehension,
		_steps_from(data, comprehension)
	)
	for ability_id in data.get("abilities", []):
		state.abilities.append(StringName(ability_id))
	return state


## A payload written before `steps` existed carries only the comprehension the
## walk accumulated, so the walk it records is that much comprehension over one
## step's share — and is therefore short by exactly the steps it never took.
static func _steps_from(data: Dictionary, comprehension: float) -> int:
	if data.has("steps"):
		return maxi(0, int(data.get("steps", 0)))
	return clampi(roundi(comprehension / STEP_COMPREHENSION), 0, ASCENT_STEPS)


func _string_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
