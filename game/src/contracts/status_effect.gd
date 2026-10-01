class_name StatusEffect
extends RefCounted

## A timed or permanent actor status. Modules own their own status ids.

var id: StringName
var remaining: float


func _init(p_id: StringName, p_remaining: float = -1.0) -> void:
	id = p_id
	remaining = p_remaining


func is_permanent() -> bool:
	return remaining < 0.0


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


func tick(delta: float) -> void:
	if not is_permanent():
		remaining = maxf(0.0, remaining - delta)
