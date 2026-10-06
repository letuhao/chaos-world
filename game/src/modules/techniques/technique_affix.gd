class_name TechniqueAffix
extends Resource

## One affix on a technique manual.
##
## An affix is a FLAT ADDITION to an option's value. It is NEVER a multiplier:
## a band is a multiplier on the authored value, and an affix is a flat addition
## to the (possibly banded) result. This is the whole of the "no second
## multiplier" rule — the defect this program already shipped once.
##
## Two kinds:
## - **Authored** (`authored = true`): fixed on the manual, applies to every copy.
## - **Rolled** (`authored = false`): banded per copy, drawn at learn time.
##
## Three target types:
## - **OPTION**: modifies the value of a specific option (e.g., `cult_qi_control`).
## - **STAT**: modifies a stat directly (e.g., `qi_control`).
## - **TECHNIQUE_PROPERTY**: modifies a technique property (e.g., `magnitude`).

enum TargetType { OPTION, STAT, TECHNIQUE_PROPERTY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## What this affix modifies.
@export var target_type: TargetType = TargetType.OPTION

## The option this affix modifies (when target_type is OPTION).
@export var target_option_id: StringName = &""

## The stat this affix modifies (when target_type is STAT).
@export var target_stat: StringName = &""

## The technique property this affix modifies (when target_type is TECHNIQUE_PROPERTY).
@export var target_property: StringName = &""

## The flat value to add to the target's value.
@export var value: float = 0.0

## Exclusivity group. Two affixes in the same group cannot both apply.
@export var exclusive_group: StringName = &""

## True = authored (fixed on manual), false = rolled (per copy).
@export var authored: bool = true

## For rolled affixes: the rarity that controls the band width.
@export var rarity: StringName = ItemRarity.COMMON


## The canonical target id, regardless of target type.
func target_id() -> StringName:
	match target_type:
		TargetType.OPTION:
			return target_option_id
		TargetType.STAT:
			return target_stat
		TargetType.TECHNIQUE_PROPERTY:
			return target_property
	return &""


## Whether this affix targets `option_id`.
func targets_option(option_id: StringName) -> bool:
	return target_type == TargetType.OPTION and target_option_id == option_id
