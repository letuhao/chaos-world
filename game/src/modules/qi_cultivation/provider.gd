class_name QiProvider
extends StatProvider

## Contributes Qi Cultivation derived stats from base attributes, realm rank,
## and qi_purity. Pure function, no scene tree dependency (ADR 0011).


func contribute(context: StatContext) -> Dictionary:
	var qi_affinity := context.value(QiStats.QI_AFFINITY)
	var qi_control := context.value(QiStats.QI_CONTROL)
	var dantian_capacity := context.value(QiStats.DANTIAN_CAPACITY)
	var spirit := context.value(Stat.SPIRIT)
	var aptitude := context.value(Stat.APTITUDE)

	var purity := _purity(context)
	var rank := _rank_index(context)
	var realm_mult := 1.0 + rank * 0.1

	return {
		QiStats.QI_REGEN_RATE: (qi_affinity * 0.3 + aptitude * 0.1) * realm_mult,
		QiStats.QI_ABSORPTION: (qi_affinity * 0.5 + spirit * 0.2) * (0.5 + purity * 0.5),
		QiStats.TECHNIQUE_COST_REDUCTION: clampf(qi_control * 0.002, 0.0, 0.5),
		QiStats.TECHNIQUE_POWER: (1.0 + qi_affinity * 0.05) * (0.5 + purity * 0.5) * realm_mult,
		QiStats.FLIGHT_SPEED: dantian_capacity * 2.0 * (1.0 + rank * 0.05),
		QiStats.QI_SENSE_RANGE: (qi_affinity * 10.0 + qi_control * 5.0) * (0.5 + purity * 0.5),
	}


func _purity(context: StatContext) -> float:
	var pool := context.resource(QiStats.QI_PURITY)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)


func _rank_index(context: StatContext) -> int:
	var state := context.path(QiPath.PATH_ID)
	if state == null:
		return 0
	return maxi(0, RealmDefaults.ladder().index_of(state.rank_id))
