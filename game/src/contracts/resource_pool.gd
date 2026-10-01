class_name ResourcePool
extends RefCounted

## A named current/max pool (health, qi, stamina, essence, ...). Modules add pools.

var id: StringName
var current: float
var maximum: float
var regen: float


func _init(p_id: StringName, p_maximum: float = 0.0) -> void:
	id = p_id
	maximum = maxf(0.0, p_maximum)
	current = maximum
	regen = 0.0


func set_maximum(value: float) -> void:
	maximum = maxf(0.0, value)
	current = clampf(current, 0.0, maximum)


func change(delta: float) -> void:
	current = clampf(current + delta, 0.0, maximum)


func ratio() -> float:
	return 0.0 if maximum <= 0.0 else current / maximum


func to_dict() -> Dictionary:
	return {"id": String(id), "current": current, "maximum": maximum, "regen": regen}


static func from_dict(data: Dictionary) -> ResourcePool:
	var pool := ResourcePool.new(StringName(data.get("id", "")), float(data.get("maximum", 0.0)))
	pool.current = clampf(float(data.get("current", pool.maximum)), 0.0, pool.maximum)
	pool.regen = float(data.get("regen", 0.0))
	return pool
