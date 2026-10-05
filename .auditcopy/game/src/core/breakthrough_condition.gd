class_name BreakthroughCondition
extends RefCounted

## Contract: a cultivation system decides when an actor may break through one path.
## Conditions may read items, partners, statuses, or other systems; the core never
## does (ADR 0003/0005). Implementations live in modules.


func can_breakthrough(_actor: Actor, _state: PathState, _context: Dictionary) -> bool:
	return false


func describe() -> String:
	return "unspecified"
