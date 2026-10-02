class_name RealmDef
extends Resource

## One realm on the shared ladder (ADR 0005). `index` is assigned by RealmLadder.

@export var id: StringName = &""
@export var display_name: String = ""
@export var tier: int = 1
@export var index: int = 0
## This realm's stat multiplier, read from the authored table in
## `core/realm_power_table.tres` (ADR 0050). AUTHORED, not derived: it is an input
## that content owns, so nothing computes it from `index` and nothing may cache a
## computed value on this object - see `RealmDefaults._all()` for the trap that
## already cost one field.
@export var power: float = 1.0
