class_name DualTechniqueDef
extends Resource

## Data-driven dual-cultivation technique. Pure numbers; the action layer reads them.
## Add a technique by authoring a `.tres`, not code (ADR 0002).

@export var id: StringName = &""
@export var display_name: String = ""
@export var essence_cost: float = 0.0
@export var qi_transfer: float = 0.0
@export var harmony_required: float = 0.0
@export var corruption_delta: float = 0.0
@export var yin_cost: float = 0.0
@export var yang_cost: float = 0.0
