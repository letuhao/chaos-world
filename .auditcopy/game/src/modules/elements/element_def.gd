class_name ElementDef
extends Resource

## Data-driven element: which elements it nourishes (`generates`) and overcomes
## (`overcomes`). Add an element by authoring a `.tres`, not code (ADR 0004).

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier: int = 1
@export var generates: Array[StringName] = []
@export var overcomes: Array[StringName] = []
@export var color: Color = Color.WHITE
