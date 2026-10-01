class_name MeridianDef
extends Resource

## Data-driven meridian definition (ADR 0017). Add a meridian by authoring a
## `.tres` or extending MeridianDefaults; no core change.

@export var id: StringName = &""
@export var display_name: String = ""
@export var type: StringName = &"primary"
@export var tier: int = 0
@export var capacity_bonus: float = 0.0
@export var flow_bonus: float = 0.0
@export var power_bonus: float = 0.0
