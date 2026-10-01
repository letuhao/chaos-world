class_name StatProvider
extends RefCounted

## Contract: a module contributes derived stats for an actor. Implementations must be
## pure (no scene tree, no mutation) and return {stat_id: float} (ADR 0002).


func contribute(_context: StatContext) -> Dictionary:
	return {}
