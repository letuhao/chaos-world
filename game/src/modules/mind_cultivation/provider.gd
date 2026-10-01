class_name MindProvider
extends StatProvider

## Contributes the module's actor-scoped derived stats from base attributes,
## resources, and the mind cultivation path rank (ADR 0013).


func contribute(context: StatContext) -> Dictionary:
	var perception := context.value(MindStats.PERCEPTION)
	var mental_clarity := context.value(MindStats.MENTAL_CLARITY)
	var spirit := context.value(Stat.SPIRIT)
	var will := context.value(Stat.WILL)
	var comprehension := context.value(Stat.COMPREHENSION)

	var mind_power_ratio := _pool_ratio(context, MindStats.MIND_POWER)
	var awareness_ratio := _pool_ratio(context, MindStats.AWARENESS)
	var rank := _mind_rank(context)
	var scaling := 1.0 + rank * 0.05

	return {
		MindStats.MENTAL_ATTACK: (perception * 2.0 + mental_clarity * 1.5) * scaling,
		MindStats.MENTAL_DEFENSE: (mental_clarity * 2.0 + will * 0.5) * scaling,
		MindStats.SPIRITUAL_SENSE_RANGE: 50.0 + perception * 5.0 + rank * 10.0,
		MindStats.CRITICAL_CHANCE: minf(0.75, 0.05 + perception * 0.003 + awareness_ratio * 0.1),
		MindStats.DODGE_CHANCE: minf(0.6, perception * 0.002 + awareness_ratio * 0.05),
		MindStats.ILLUSION_RESISTANCE: minf(0.8, mental_clarity * 0.004 + will * 0.002),
		MindStats.MIND_TECHNIQUE_POWER: (perception * 1.5 + mental_clarity * 1.0) * scaling,
		MindStats.COMPREHENSION_BONUS: 1.0 + comprehension * 0.01 + rank * 0.02,
	}


func _mind_rank(context: StatContext) -> float:
	var state := context.path(MindPath.PATH_ID)
	if state == null:
		return 0.0
	return float(maxi(0, RealmDefaults.ladder().index_of(state.rank_id)))


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)
