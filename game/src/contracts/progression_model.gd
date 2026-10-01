class_name ProgressionModel
extends RefCounted

## Contract: decides how a cultivation path advances. Implementations must be pure
## and must not depend on the scene tree. See ADR 0003.


func can_advance(_state: PathState, _context: Dictionary) -> bool:
	return false


func advance(_state: PathState, _context: Dictionary) -> void:
	pass
