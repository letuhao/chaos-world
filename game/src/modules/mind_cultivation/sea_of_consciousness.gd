class_name SeaOfConsciousness
extends RefCounted

## Thức Hải — Sea of Consciousness (ADR 0016). The mind's energy reservoir,
## located in the upper dantian/head region. Stores mind power and is the
## mind-cultivation analogue of the Đan Điền (ADR 0014) and Huyệt (ADR 0015).

const SHALLOW := &"shallow"
const DEEP := &"deep"
const VAST := &"vast"

var tier: StringName = SHALLOW
var capacity: float = 100.0
var current: float = 0.0
var clarity: float = 0.5
var turbulence: float = 0.0


## Stored mind power as a 0..1 fraction of capacity.
func ratio() -> float:
	return 0.0 if capacity <= 0.0 else clampf(current / capacity, 0.0, 1.0)


func is_full() -> bool:
	return current >= capacity


func fill(amount: float) -> void:
	current = clampf(current + amount, 0.0, capacity)


func drain(amount: float) -> void:
	current = clampf(current - amount, 0.0, capacity)


func add_turbulence(amount: float) -> void:
	turbulence = clampf(turbulence + amount, 0.0, 1.0)


func calm(amount: float) -> void:
	turbulence = clampf(turbulence - amount, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"tier": String(tier),
		"capacity": capacity,
		"current": current,
		"clarity": clarity,
		"turbulence": turbulence,
	}


static func from_dict(data: Dictionary) -> SeaOfConsciousness:
	var sea := SeaOfConsciousness.new()
	sea.tier = StringName(data.get("tier", SHALLOW))
	sea.capacity = float(data.get("capacity", 100.0))
	sea.current = float(data.get("current", 0.0))
	sea.clarity = float(data.get("clarity", 0.5))
	sea.turbulence = float(data.get("turbulence", 0.0))
	return sea
