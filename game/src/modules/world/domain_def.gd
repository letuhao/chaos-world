class_name DomainDef
extends Resource

## Data-driven domain / secret realm (ADR 0008). Hosts bosses.

@export var id: StringName = &""
@export var display_name: String = ""
@export var boss_ids: Array[StringName] = []
