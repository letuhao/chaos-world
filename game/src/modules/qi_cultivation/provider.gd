class_name QiProvider
extends StatProvider

## Contributes Qi Cultivation derived stats from base attributes, the realm
## factor, and the meridian network. Pure function, no scene tree dependency
## (ADR 0011).
##
## The realm factor is ONE bounded per-realm number, `QiRealmProfile.factor`, and
## it is a RATE: how much a unit of this realm's circulation counts, never how
## strong a thing from this realm is. The path's real magnitudes live where they
## belong — `QiRealmSeed.dantian_capacity` for the reservoir, applied once by
## `QiTraining.synchronize`, and `RealmScaling` (core) for the shared combat
## stats — so this provider must not also scale by the realm's strength. The body
## and mind providers read the same number for the same realm.


func contribute(context: StatContext) -> Dictionary:
	var qi_affinity := context.value(QiStats.QI_AFFINITY)
	var qi_control := context.value(QiStats.QI_CONTROL)
	var dantian_capacity := context.value(QiStats.DANTIAN_CAPACITY)
	var spirit := context.value(Stat.SPIRIT)
	var aptitude := context.value(Stat.APTITUDE)

	var factor := _realm_factor(context)
	var meridian_bonus := _meridian_flow_bonus(context)

	return {
		QiStats.QI_REGEN_RATE:
		(qi_affinity * 0.3 + aptitude * 0.1) * factor * (1.0 + meridian_bonus),
		QiStats.QI_ABSORPTION: (qi_affinity * 0.5 + spirit * 0.2) * (1.0 + meridian_bonus),
		QiStats.TECHNIQUE_COST_REDUCTION: clampf(qi_control * 0.002, 0.0, 0.5),
		QiStats.TECHNIQUE_POWER: (1.0 + qi_affinity * 0.05) * factor,
		QiStats.FLIGHT_SPEED: dantian_capacity * 2.0 * factor,
		QiStats.QI_SENSE_RANGE: qi_affinity * 10.0 + qi_control * 5.0,
	}


func _meridian_flow_bonus(context: StatContext) -> float:
	var network := context.component(&"meridians")
	if network is MeridianNetwork:
		return network.get_flow_bonus()
	return 0.0


## The realm factor, or neutral when the path is unstarted. An unknown realm id
## resolves to neutral inside the profile class, so a path holding a stale rank
## degrades instead of throwing.
func _realm_factor(context: StatContext) -> float:
	var state := context.path(QiPath.PATH_ID)
	if state == null or state.rank_id == &"":
		return QiRealmProfile.NEUTRAL
	return QiRealmProfile.factor(state.rank_id)
