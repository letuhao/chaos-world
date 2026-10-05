class_name AscensionProvider
extends StatProvider

## Emits derived stats from AscensionState (ADR 0021). Reads the ascension
## component attached to the actor. Returns empty when no ascension exists.


func contribute(context: StatContext) -> Dictionary:
	var ascension: AscensionState = context.component(&"ascension")
	if ascension == null:
		return {}
	return {
		&"ascension_stage": float(ascension.stage),
		&"ascension_dao_level": float(ascension.dao_level),
		&"ascension_comprehension": ascension.comprehension,
		&"ascension_complete": 1.0 if ascension.is_complete() else 0.0,
	}
