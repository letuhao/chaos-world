class_name Acupoint
extends RefCounted

## Huyệt — acupoint storage (ADR 0015). Each acupoint holds a body essence pool
## whose capacity scales with realm. Blocked acupoints cannot store or release
## essence until repaired.

const MINOR := &"minor"
const MAJOR := &"major"
const CELESTIAL := &"celestial"

var id: StringName
var tier: StringName = MINOR
var capacity: float = 100.0
var current: float = 0.0
var quality: float = 0.5
var blocked: bool = false


func effective_capacity() -> float:
	return 0.0 if blocked else capacity


func is_full() -> bool:
	return current >= effective_capacity()


func fill(amount: float) -> void:
	if blocked:
		return
	current = clampf(current + amount, 0.0, effective_capacity())


func drain(amount: float) -> void:
	if blocked:
		return
	current = clampf(current - amount, 0.0, effective_capacity())


func block() -> void:
	blocked = true
	current = 0.0


func clear_block() -> void:
	blocked = false


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"tier": String(tier),
		"capacity": capacity,
		"current": current,
		"quality": quality,
		"blocked": blocked,
	}


static func from_dict(data: Dictionary) -> Acupoint:
	var point := Acupoint.new()
	point.id = StringName(data.get("id", ""))
	point.tier = StringName(data.get("tier", MINOR))
	point.capacity = float(data.get("capacity", 100.0))
	point.current = float(data.get("current", 0.0))
	point.quality = float(data.get("quality", 0.5))
	point.blocked = bool(data.get("blocked", false))
	return point
