class_name BodyProvider
extends StatProvider

## Contributes body-cultivation derived stats from base attributes, body integrity
## ratio, path rank, and meridian bonuses (ADR 0012, ADR 0015).


func contribute(context: StatContext) -> Dictionary:
	var bone_density := context.value(BodyStats.BONE_DENSITY)
	var muscle_fiber := context.value(BodyStats.MUSCLE_FIBER)
	var organ_vitality := context.value(BodyStats.ORGAN_VITALITY)
	var physique := context.value(Stat.PHYSIQUE)

	var integrity_ratio := _pool_ratio(context, BodyStats.BODY_INTEGRITY)
	var integrity_factor := 0.5 + 0.5 * integrity_ratio

	var multiplier := _realm_multiplier(context)
	var meridian_power := _meridian_power_bonus(context)

	var scaling := integrity_factor * multiplier * (1.0 + meridian_power)

	return {
		BodyStats.PHYSICAL_ATTACK: (muscle_fiber * 2.0 + bone_density * 1.0) * scaling,
		BodyStats.PHYSICAL_DEFENSE: (bone_density * 1.5 + organ_vitality * 1.0) * scaling,
		BodyStats.MOVE_SPEED: muscle_fiber * 0.5 * scaling,
		BodyStats.CARRY_CAPACITY: (bone_density * 10.0 + muscle_fiber * 5.0) * scaling,
		BodyStats.REGENERATION: organ_vitality * 0.3 * scaling,
		BodyStats.POISE: (bone_density * 0.8 + physique * 0.5) * scaling,
		BodyStats.BODY_CULTIVATION_POWER:
		(bone_density + muscle_fiber + organ_vitality) * 0.5 * scaling,
	}


func _realm_multiplier(context: StatContext) -> float:
	var state := context.path(BodyPath.PATH_ID)
	if state == null:
		return 1.0
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	if realm == null:
		return 1.0
	return realm.power


func _meridian_power_bonus(context: StatContext) -> float:
	var meridians: MeridianNetwork = context.component(&"meridians")
	if meridians == null:
		return 0.0
	return meridians.get_power_bonus()


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)
