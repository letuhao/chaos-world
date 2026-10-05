class_name WorldLawDef
extends Resource

## Data-driven world law (ADR 0019/0045). One of six law groups.

@export var law_id: StringName = &""
@export var display_name: String = ""
@export var group: StringName = &""
@export var value_min: float = 0.0
@export var value_max: float = 1.0
@export var description: String = ""
@export var tier_ids: Array[StringName] = []
