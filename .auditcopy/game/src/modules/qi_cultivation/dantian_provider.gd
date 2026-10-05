class_name DantianProvider
extends StatProvider

## Emits derived stats from Dantian state (ADR 0014). Reads the dantian
## component and the shared qi reservoir pool from the stat context.


func contribute(context: StatContext) -> Dictionary:
	var dantian: Dantian = context.component(&"dantian")
	if dantian == null:
		return {}
	var qi_pool := context.resource(QiStats.QI)
	if qi_pool == null:
		return {}
	var full := 1.0 if qi_pool.current >= dantian.effective_capacity() else 0.0
	return {
		QiStats.DANTIAN_CAPACITY: dantian.effective_capacity(),
		QiStats.DANTIAN_QUALITY: dantian.quality,
		QiStats.DANTIAN_FULL: full,
	}
