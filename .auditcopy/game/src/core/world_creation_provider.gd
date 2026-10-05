class_name WorldCreationProvider
extends StatProvider

## Emits derived stats from WorldState (ADR 0019). Reads the world component
## attached to the actor. Returns empty when no world exists.


func contribute(context: StatContext) -> Dictionary:
	var world: WorldState = context.component(&"world")
	if world == null:
		return {}
	return {
		&"world_size": world.size,
		&"world_stability": world.stability,
		&"world_will": world.will_strength,
		&"world_tier": _tier_to_int(world.tier),
	}


func _tier_to_int(tier: StringName) -> int:
	match tier:
		WorldState.MICRO:
			return 0
		WorldState.SMALL:
			return 1
		WorldState.GREAT:
			return 2
	return 0
