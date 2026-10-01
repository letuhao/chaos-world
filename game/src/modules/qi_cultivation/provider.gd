class_name QiProvider
extends StatProvider

## Contributes Qi Cultivation derived stats from base attributes, realm profile
## factors, and qi_purity. Pure function, no scene tree dependency (ADR 0011).


func contribute(context: StatContext) -> Dictionary:
	var qi_affinity := context.value(QiStats.QI_AFFINITY)
	var qi_control := context.value(QiStats.QI_CONTROL)
	var dantian_capacity := context.value(QiStats.DANTIAN_CAPACITY)
	var spirit := context.value(Stat.SPIRIT)
	var aptitude := context.value(Stat.APTITUDE)

	var purity := _purity(context)
	var profile := _profile_factors(context)
	var meridian_bonus := _meridian_flow_bonus(context)

	return {
		QiStats.QI_REGEN_RATE:
		(qi_affinity * 0.3 + aptitude * 0.1) * profile.throughput * (1.0 + meridian_bonus),
		QiStats.QI_ABSORPTION:
		(qi_affinity * 0.5 + spirit * 0.2) * (0.5 + purity * 0.5) * (1.0 + meridian_bonus),
		QiStats.TECHNIQUE_COST_REDUCTION: clampf(qi_control * 0.002, 0.0, 0.5),
		QiStats.TECHNIQUE_POWER:
		(1.0 + qi_affinity * 0.05) * (0.5 + purity * 0.5) * profile.technique,
		QiStats.FLIGHT_SPEED: dantian_capacity * 2.0 * profile.throughput,
		QiStats.QI_SENSE_RANGE: (qi_affinity * 10.0 + qi_control * 5.0) * (0.5 + purity * 0.5),
	}


func _meridian_flow_bonus(context: StatContext) -> float:
	var network := context.component(&"meridians")
	if network is MeridianNetwork:
		return network.get_flow_bonus()
	return 0.0


func _purity(context: StatContext) -> float:
	var pool := context.resource(QiStats.QI_PURITY)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)


## Profile factors from the realm seed. Returns neutral factors when no seed
## is loaded (e.g. before path initiation).
func _profile_factors(context: StatContext) -> Dictionary:
	var state := context.path(QiPath.PATH_ID)
	if state == null or state.rank_id == &"":
		return {"throughput": 1.0, "technique": 1.0}
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return {"throughput": 1.0, "technique": 1.0}
	return {"throughput": seed.throughput_factor, "technique": seed.technique_factor}
