class_name SeaProvider
extends StatProvider

## Emits derived stats from Sea of Consciousness state (ADR 0016). Reads the
## sea component attached to the actor. Capacity and fullness come from the
## actor's mind_power pool via the sea.


func contribute(context: StatContext) -> Dictionary:
	var sea: SeaOfConsciousness = context.component(&"sea_of_consciousness")
	if sea == null:
		return {}
	var pool := context.resource(MindStats.MIND_POWER)
	var capacity := pool.maximum if pool != null else sea.structural_capacity
	var current := pool.current if pool != null else 0.0
	var usable := sea.effective_capacity()
	var full := 1.0 if (pool != null and current >= usable) else 0.0
	return {
		MindStats.SEA_CAPACITY: capacity,
		MindStats.SEA_CLARITY: sea.clarity,
		MindStats.SEA_TURBULENCE: sea.turbulence,
		MindStats.SEA_FULL: full,
	}
