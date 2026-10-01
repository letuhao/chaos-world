class_name MeridianState
extends RefCounted

## Per-meridian runtime state (ADR 0017). One instance per meridian on an actor.

var id: StringName
var state: StringName = &"closed"
var tier: int = 0
var capacity_bonus: float = 0.0
var flow_bonus: float = 0.0
var power_bonus: float = 0.0


func is_open() -> bool:
	return state != &"closed"


func is_damaged() -> bool:
	return state == &"damaged"


func get_bonus() -> float:
	if state == &"damaged":
		return 0.5
	return 1.0
