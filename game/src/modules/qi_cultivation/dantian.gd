class_name Dantian
extends RefCounted

## Qi storage (ADR 0014). Three tiers aligned to the shared realm ladder.
## Damage reduces effective capacity by 25% until healed.

const LOWER := &"lower"
const MIDDLE := &"middle"
const UPPER := &"upper"

var tier: StringName = LOWER
var capacity: float = 100.0
var current: float = 0.0
var quality: float = 0.5
var damaged: bool = false


func effective_capacity() -> float:
	return capacity * 0.75 if damaged else capacity


func is_full() -> bool:
	return current >= effective_capacity()


func fill(amount: float) -> void:
	current = clampf(current + amount, 0.0, effective_capacity())


func drain(amount: float) -> void:
	current = clampf(current - amount, 0.0, effective_capacity())


func damage() -> void:
	damaged = true
	current = clampf(current, 0.0, effective_capacity())


func heal() -> void:
	damaged = false


func to_dict() -> Dictionary:
	return {
		"tier": String(tier),
		"capacity": capacity,
		"current": current,
		"quality": quality,
		"damaged": damaged,
	}


static func from_dict(data: Dictionary) -> Dantian:
	var dantian := Dantian.new()
	dantian.tier = StringName(data.get("tier", LOWER))
	dantian.capacity = float(data.get("capacity", 100.0))
	dantian.current = float(data.get("current", 0.0))
	dantian.quality = float(data.get("quality", 0.5))
	dantian.damaged = bool(data.get("damaged", false))
	return dantian
