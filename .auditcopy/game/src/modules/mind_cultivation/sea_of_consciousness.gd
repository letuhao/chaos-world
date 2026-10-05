class_name SeaOfConsciousness
extends RefCounted

## Thức Hải — Sea of Consciousness (ADR 0016). The mind's structural reservoir.
## Current/capacity live in the actor's `mind_power` ResourcePool (single
## reservoir) — this component reads and mutates that pool directly, matching
## the Dantian/qi pattern (ADR 0014). The sea owns structural tier, clarity,
## turbulence, purity, and trained stage.

signal changed

const SHALLOW := &"shallow"
const DEEP := &"deep"
const VAST := &"vast"

var tier: StringName = SHALLOW
var clarity: float = 0.5
var turbulence: float = 0.0
var purity: float = 0.5
## Structural capacity from training/profile (not equipment-inflated).
var structural_capacity: float = 100.0
## Trained stage within the current tier (0 = untrained).
var trained_stage: int = 0


## Effective capacity: structural capacity reduced by turbulence.
func effective_capacity() -> float:
	return structural_capacity * (1.0 - turbulence * 0.5)


## Current mind power from the shared reservoir pool.
func current(actor: Actor) -> float:
	var pool := actor.resource(MindStats.MIND_POWER)
	return pool.current if pool != null else 0.0


## Maximum mind power from the shared reservoir pool.
func maximum(actor: Actor) -> float:
	var pool := actor.resource(MindStats.MIND_POWER)
	return pool.maximum if pool != null else 0.0


## Stored mind power as a 0..1 fraction of usable capacity.
func ratio(actor: Actor) -> float:
	var usable := effective_capacity()
	return 0.0 if usable <= 0.0 else clampf(current(actor) / usable, 0.0, 1.0)


## Full means the shared pool reached its own maximum. Turbulence lowers that
## maximum rather than introducing a second target the reservoir cannot reach.
func is_full(actor: Actor) -> bool:
	return current(actor) >= maximum(actor) - 0.0001


func fill(actor: Actor, amount: float) -> void:
	var pool := actor.resource(MindStats.MIND_POWER)
	if pool != null:
		pool.change(amount)
		_emit_changed()


func drain(actor: Actor, amount: float) -> void:
	var pool := actor.resource(MindStats.MIND_POWER)
	if pool != null:
		pool.change(-amount)
		_emit_changed()


func add_turbulence(amount: float) -> void:
	turbulence = clampf(turbulence + amount, 0.0, 1.0)
	_emit_changed()


func calm(amount: float) -> void:
	turbulence = clampf(turbulence - amount, 0.0, 1.0)
	_emit_changed()


func set_tier(new_tier: StringName) -> void:
	if tier != new_tier:
		tier = new_tier
		_emit_changed()


func set_clarity(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if clarity != clamped:
		clarity = clamped
		_emit_changed()


func set_purity(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if purity != clamped:
		purity = clamped
		_emit_changed()


func set_structural_capacity(value: float) -> void:
	if structural_capacity != value:
		structural_capacity = maxf(0.0, value)
		_emit_changed()


func _emit_changed() -> void:
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"tier": String(tier),
		"clarity": clarity,
		"turbulence": turbulence,
		"purity": purity,
		"structural_capacity": structural_capacity,
		"trained_stage": trained_stage,
	}


static func from_dict(data: Dictionary) -> SeaOfConsciousness:
	var sea := SeaOfConsciousness.new()
	sea.tier = StringName(data.get("tier", SHALLOW))
	sea.clarity = float(data.get("clarity", 0.5))
	sea.turbulence = float(data.get("turbulence", 0.0))
	sea.purity = float(data.get("purity", 0.5))
	sea.structural_capacity = float(data.get("structural_capacity", 100.0))
	sea.trained_stage = int(data.get("trained_stage", 0))
	return sea
