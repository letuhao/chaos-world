class_name InsideWorldProvider
extends StatProvider

## Emits derived stats from InsideWorld state (ADR 0018). Reads the inside_world
## component attached to the actor. Returns empty when no world exists.


func contribute(context: StatContext) -> Dictionary:
	var world: InsideWorld = context.component(&"inside_world")
	if world == null:
		return {}
	return {
		&"inside_world_size": world.size,
		&"inside_world_stability": world.stability,
		&"inside_world_qi_density": world.qi_density,
		&"inside_world_time_flow": world.time_flow,
	}
