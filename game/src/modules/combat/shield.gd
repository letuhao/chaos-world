class_name Shield
extends RefCounted

## Shield as a ResourcePool with absorb semantics (DEF-0006).
## Damage depletes the shield before health. Emits `changed` on mutation.

signal changed
signal depleted

var pool: ResourcePool
var _on_changed: Callable


func _init(p_id: StringName = &"shield", p_maximum: float = 0.0) -> void:
	pool = ResourcePool.new(p_id, p_maximum)
	_on_changed = func() -> void: changed.emit()
	pool.changed.connect(_on_changed)


func absorb(damage: float) -> float:
	## Absorb damage; return overflow that passes through.
	var absorbed := minf(pool.current, damage)
	pool.change(-absorbed)
	if pool.current <= 0.0:
		depleted.emit()
	return damage - absorbed


func is_active() -> bool:
	return pool.current > 0.0


func to_dict() -> Dictionary:
	return pool.to_dict()
