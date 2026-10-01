class_name SeaProvider
extends StatProvider

## Emits derived stats from Sea of Consciousness state (ADR 0016). Reads the
## sea component attached to the actor.


func contribute(context: StatContext) -> Dictionary:
	var sea: SeaOfConsciousness = context.component(&"sea_of_consciousness")
	if sea == null:
		return {}
	return {
		MindStats.SEA_CAPACITY: sea.capacity,
		MindStats.SEA_CLARITY: sea.clarity,
		MindStats.SEA_TURBULENCE: sea.turbulence,
		MindStats.SEA_FULL: 1.0 if sea.is_full() else 0.0,
	}
