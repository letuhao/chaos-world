class_name StatModifier
extends RefCounted

## A source-tagged stat modifier. `derived = (base + flat) * (1 + percent) * mult`.

var stat: StringName
var op: Stat.Op
var value: float
var source: StringName


func _init(p_stat: StringName, p_op: Stat.Op, p_value: float, p_source: StringName = &"") -> void:
	stat = p_stat
	op = p_op
	value = p_value
	source = p_source
