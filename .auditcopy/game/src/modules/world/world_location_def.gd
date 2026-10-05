class_name WorldLocationDef
extends Resource

## Data-driven world location (ADR 0045). A place within a world tier.

@export var location_id: StringName = &""
@export var display_name: String = ""
@export var tier: StringName = &""
@export var faction_id: StringName = &""
@export var resources: Array[StringName] = []
@export var inhabitant_types: Array[StringName] = []
@export var danger_level: int = 1
