class_name WorldInhabitantDef
extends Resource

## Data-driven world inhabitant (ADR 0045). A life form within a world.

@export var inhabitant_id: StringName = &""
@export var display_name: String = ""
@export var type: StringName = &""
@export var tier_ids: Array[StringName] = []
@export var loyalty_min: float = 0.0
@export var loyalty_max: float = 1.0
@export var combat_power_min: float = 0.0
@export var combat_power_max: float = 0.0
