class_name ItemDef
extends Resource

## Data-driven item definition (ADR 0007). Author as a `.tres`; no code needed to
## add an item.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = ItemCategory.MISC
@export var subcategory: StringName = &""
@export var grade: StringName = ItemGrade.MORTAL
@export var stackable: bool = true
@export var max_stack: int = 99
@export var value: int = 0
@export var tags: Array[StringName] = []
@export var description: String = ""
@export var flat_modifiers: Dictionary = {}
@export var percent_modifiers: Dictionary = {}


func is_equipment() -> bool:
	return category == ItemCategory.EQUIPMENT


func required_tier() -> int:
	return ItemGrade.required_tier(grade)


func build_modifiers(source: StringName) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	for key in flat_modifiers.keys():
		modifiers.append(
			StatModifier.new(StringName(key), Stat.Op.FLAT, float(flat_modifiers[key]), source)
		)
	for key in percent_modifiers.keys():
		modifiers.append(
			StatModifier.new(
				StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), source
			)
		)
	return modifiers
