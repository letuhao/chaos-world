class_name BossDef
extends Resource

## Data-driven boss (ADR 0008). Spawns in a domain and drops loot items.

@export var id: StringName = &""
@export var display_name: String = ""
@export var domain_id: StringName = &""
@export var loot: Array[StringName] = []
