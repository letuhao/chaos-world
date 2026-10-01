class_name AcupointProvider
extends StatProvider

## Emits derived stats from acupoint state (ADR 0015). Reads the AcupointSet
## component attached to the actor.


func contribute(context: StatContext) -> Dictionary:
	var acupoint_set: AcupointSet = context.component(&"acupoints")
	if acupoint_set == null:
		return {}
	return {
		BodyStats.ACUPOINT_QUALITY: acupoint_set.average_quality(),
		BodyStats.ACUPOINT_COUNT: float(acupoint_set.open_count()),
		BodyStats.ACUPOINT_BLOCKED_COUNT: float(acupoint_set.blocked_count()),
	}
