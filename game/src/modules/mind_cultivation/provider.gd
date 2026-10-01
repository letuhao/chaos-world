class_name MindProvider
extends StatProvider

## Contributes the module's actor-scoped derived stats from base attributes,
## resources, and the mind cultivation path rank (ADR 0013/0016). Uses the
## realm profile factors (C/F/T) instead of a linear rank multiplier.


func contribute(context: StatContext) -> Dictionary:
	var perception := context.value(MindStats.PERCEPTION)
	var mental_clarity := context.value(MindStats.MENTAL_CLARITY)
	var spirit := context.value(Stat.SPIRIT)
	var will := context.value(Stat.WILL)
	var comprehension := context.value(Stat.COMPREHENSION)

	var mind_power_ratio := _pool_ratio(context, MindStats.MIND_POWER)
	var awareness_ratio := _pool_ratio(context, MindStats.AWARENESS)
	var technique_factor := _technique_factor(context)
	var meridian_power := _meridian_power_bonus(context)

	return {
		MindStats.MENTAL_ATTACK: (perception * 2.0 + mental_clarity * 1.5) * technique_factor,
		MindStats.MENTAL_DEFENSE:
		(mental_clarity * 2.0 + will * 0.5) * technique_factor * (1.0 + meridian_power),
		MindStats.SPIRITUAL_SENSE_RANGE: 50.0 + perception * 5.0 + technique_factor * 10.0,
		MindStats.CRITICAL_CHANCE: minf(0.75, 0.05 + perception * 0.003 + awareness_ratio * 0.1),
		MindStats.DODGE_CHANCE: minf(0.6, perception * 0.002 + awareness_ratio * 0.05),
		MindStats.ILLUSION_RESISTANCE: minf(0.8, mental_clarity * 0.004 + will * 0.002),
		MindStats.MIND_TECHNIQUE_POWER:
		(perception * 1.5 + mental_clarity * 1.0) * technique_factor * (1.0 + meridian_power),
		MindStats.COMPREHENSION_BONUS: 1.0 + comprehension * 0.01 + technique_factor * 0.02,
	}


func _meridian_power_bonus(context: StatContext) -> float:
	var network := context.component(&"meridians")
	if network is MeridianNetwork:
		return network.get_power_bonus()
	return 0.0


func _technique_factor(context: StatContext) -> float:
	"""Realm profile technique factor T = P^0.55 (ADR 0013/0016)."""
	var state := context.path(MindPath.PATH_ID)
	if state == null:
		return 1.0
	var ladder := RealmDefaults.ladder()
	var index := ladder.index_of(state.rank_id)
	if index < 0:
		return 1.0
	var tier := ladder.realm(state.rank_id).tier
	var power := _power_budget(index, tier)
	return pow(power, 0.55)


func _power_budget(index: int, tier: int) -> float:
	"""Reference power budget P for a realm (ADR 0013/0016)."""
	var local := index + 1
	if tier == 1:
		return 1.0 * (1.25 ** (local - 1))
	if tier == 2:
		return 8.0 * (1.22 ** (local - 1))
	if tier == 3:
		return 55.0 * (1.20 ** (local - 1))
	return 330.0 * (1.35 ** (local - 1))


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)
