class_name RecipeDef
extends Resource

## Data-driven crafting recipe (ADR 0008). Inputs/outputs reference item ids.

@export var id: StringName = &""
@export var display_name: String = ""
@export var station: StringName = &""
@export var inputs: Array[StringName] = []
@export var outputs: Array[StringName] = []
