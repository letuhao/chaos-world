class_name BodyProvider
extends StatProvider

## Contributes body-cultivation derived stats from base attributes, body integrity
## ratio, realm profile factors, and meridian bonuses (ADR 0012, ADR 0015, ADR 0023).
##
## Profile factors (P/C/F/T) replace the old linear rank multiplier. P is a
## reference power budget, never a stat multiplier. C scales capacity, F scales
## throughput, T scales technique power. The formulas are:
##   Mortal:       P = 1   * 1.25^(local-1)
##   Spirit:       P = 8   * 1.22^(local-1)
##   Immortal:     P = 55  * 1.20^(local-1)
##   Transcendent: P = 330 * 1.35^(local-1)
##   C = P^0.85, F = P^0.40, T = P^0.55

const TIER_BASE := [1.0, 8.0, 55.0, 330.0]
const TIER_GROWTH := [1.25, 1.22, 1.20, 1.35]


func contribute(context: StatContext) -> Dictionary:
	var bone_density := context.value(BodyStats.BONE_DENSITY)
	var muscle_fiber := context.value(BodyStats.MUSCLE_FIBER)
	var organ_vitality := context.value(BodyStats.ORGAN_VITALITY)
	var physique := context.value(Stat.PHYSIQUE)

	var integrity_ratio := _pool_ratio(context, BodyStats.BODY_INTEGRITY)
	var integrity_factor := 0.5 + 0.5 * integrity_ratio

	var profile := _profile_factors(context)
	var meridian_power := _meridian_power_bonus(context)

	# T (technique factor) scales combat stats; F (throughput) scales speed/regen;
	# C (capacity) scales carry capacity. P is never a direct multiplier.
	var t_factor: float = float(profile.T) * (1.0 + meridian_power)
	var f_factor: float = float(profile.F) * (1.0 + meridian_power)
	var c_factor: float = float(profile.C) * (1.0 + meridian_power)

	return {
		BodyStats.PHYSICAL_ATTACK:
		(muscle_fiber * 2.0 + bone_density * 1.0) * integrity_factor * t_factor,
		BodyStats.PHYSICAL_DEFENSE:
		(bone_density * 1.5 + organ_vitality * 1.0) * integrity_factor * t_factor,
		BodyStats.MOVE_SPEED: muscle_fiber * 0.5 * integrity_factor * f_factor,
		BodyStats.CARRY_CAPACITY:
		(bone_density * 10.0 + muscle_fiber * 5.0) * integrity_factor * c_factor,
		BodyStats.REGENERATION: organ_vitality * 0.3 * integrity_factor * f_factor,
		BodyStats.POISE: (bone_density * 0.8 + physique * 0.5) * integrity_factor * t_factor,
		BodyStats.BODY_CULTIVATION_POWER:
		(bone_density + muscle_fiber + organ_vitality) * 0.5 * integrity_factor * t_factor,
	}


func _profile_factors(context: StatContext) -> Dictionary:
	var state := context.path(BodyPath.PATH_ID)
	if state == null:
		return {"P": 1.0, "C": 1.0, "F": 1.0, "T": 1.0}
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	if realm == null:
		return {"P": 1.0, "C": 1.0, "F": 1.0, "T": 1.0}
	var tier := realm.tier
	var local := _local_index(realm) + 1
	var base: float = TIER_BASE[tier - 1] if tier >= 1 and tier <= 4 else 1.0
	var growth: float = TIER_GROWTH[tier - 1] if tier >= 1 and tier <= 4 else 1.0
	var p: float = base * pow(growth, local - 1.0)
	return {
		"P": p,
		"C": pow(p, 0.85),
		"F": pow(p, 0.40),
		"T": pow(p, 0.55),
	}


func _local_index(realm: RealmDef) -> int:
	# Index within the tier (0-based). Realms are ordered 1-9 Mortal, 10-18 Spirit,
	# 19-27 Immortal, 28-30 Transcendent.
	var tier := realm.tier
	var index := realm.index
	match tier:
		1:
			return index
		2:
			return index - 9
		3:
			return index - 18
		4:
			return index - 27
	return index


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
