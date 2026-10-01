class_name DantianProvider
extends StatProvider

## Emits derived stats from Dantian state (ADR 0014). Reads the dantian
## component attached to the actor.


func contribute(context: StatContext) -> Dictionary:
	var dantian: Dantian = context.component(&"dantian")
	if dantian == null:
		return {}
	return {
		QiStats.DANTIAN_CAPACITY: dantian.effective_capacity(),
		QiStats.DANTIAN_QUALITY: dantian.quality,
		QiStats.DANTIAN_FULL: 1.0 if dantian.is_full() else 0.0,
	}
