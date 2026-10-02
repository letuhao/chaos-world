class_name WorldFactionDef
extends Resource

## Data-driven world faction (ADR 0047). Controls locations and inhabitants.

@export var faction_id: StringName = &""
@export var display_name: String = ""
@export var dao_alignment: StringName = &""
@export var home_tier: StringName = &""
@export var philosophy: String = ""
@export var relationships: Array[Dictionary] = []
