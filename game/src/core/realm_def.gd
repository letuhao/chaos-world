class_name RealmDef
extends Resource

## One realm on the shared ladder (ADR 0005). `index` is assigned by RealmLadder.

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier: int = 1
@export var index: int = 0
@export var power: float = 1.0
