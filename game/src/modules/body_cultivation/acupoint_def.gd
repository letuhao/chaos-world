class_name AcupointDef
extends Resource

## Immutable seed metadata; mutable essence and quality belong to Acupoint.

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier: StringName = &"minor"
@export var unlock_index: int = 0
@export var meridian_id: StringName = &""
@export var base_capacity: float = 50.0
