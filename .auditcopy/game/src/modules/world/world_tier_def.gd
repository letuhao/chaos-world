class_name WorldTierDef
extends Resource

## Data-driven world tier (ADR 0046). Maps a realm band to world properties.

@export var tier_id: StringName = &""
@export var display_name: String = ""
@export var realm_min: int = 1
@export var realm_max: int = 9
@export var law_slots: int = 3
@export var available_life_forms: Array[StringName] = []
@export var upkeep_rate_min: float = 0.0
@export var upkeep_rate_max: float = 0.0
@export var time_flow_min: float = 1.0
@export var time_flow_max: float = 1.0
@export var size_min: float = 0.0
@export var size_max: float = 0.0
