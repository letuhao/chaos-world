class_name BodyProvider
extends StatProvider

## Body-cultivation derived stats from base attributes, body integrity ratio,
## realm profile factors, and meridian bonuses (ADR 0012, ADR 0015, ADR 0023).
##
## Core-owned stats (attack, defense, move speed, poise) are contributed
## ADDITIVELY on top of the core baseline, because a provider value replaces the
## baseline for any id it emits (ADR 0026). Module-owned stats are defined
## outright. See stats.gd for the alias/no-alias split.
##
## Every realm-shaped read here is ONE bounded per-realm factor,
## `BodyRealmProfile.factor`, applied to every contribution. It is a RATE, not a
## magnitude: the realm's actual magnitudes live in the two places that own them —
## `RealmScaling` (core) for the shared combat stats, and
## `BodyRealmSeed.integrity_maximum` for the body's reservoir. The qi and mind
## providers read the same number for the same realm, so the three paths cannot
## drift apart on a private curve.


func contribute(context: StatContext) -> Dictionary:
	var bone_density := context.value(BodyStats.BONE_DENSITY)
	var muscle_fiber := context.value(BodyStats.MUSCLE_FIBER)
	var organ_vitality := context.value(BodyStats.ORGAN_VITALITY)
	var physique := context.value(Stat.PHYSIQUE)

	var integrity_ratio := _pool_ratio(context, BodyStats.BODY_INTEGRITY)
	var integrity_factor := 0.5 + 0.5 * integrity_ratio

	var meridian_power := _meridian_power_bonus(context)

	# Core-owned stats are contributed ADDITIVELY. A provider value becomes the
	# baseline for whatever id it emits (ADR 0026), so emitting an absolute body
	# value for `move_speed` would erase the core `100 + agility * 2` — a 200x
	# drop the moment the body path is attached. Body cultivation is a
	# specialization: it adds to the shared stat, it never replaces it.
	var shaped := integrity_factor * _realm_factor(context) * (1.0 + meridian_power)
	var attack_bonus := (muscle_fiber * 2.0 + bone_density * 1.0) * shaped
	var defense_bonus := (bone_density * 1.5 + organ_vitality * 1.0) * shaped
	var poise_bonus := (bone_density * 0.8 + physique * 0.5) * shaped
	var speed_bonus := muscle_fiber * 0.5 * shaped

	return {
		# Core-owned: additive so the core baseline always survives.
		BodyStats.PHYSICAL_ATTACK: context.value(BodyStats.PHYSICAL_ATTACK) + attack_bonus,
		BodyStats.PHYSICAL_DEFENSE: context.value(BodyStats.PHYSICAL_DEFENSE) + defense_bonus,
		BodyStats.MOVE_SPEED: context.value(BodyStats.MOVE_SPEED) + speed_bonus,
		BodyStats.POISE: context.value(BodyStats.POISE) + poise_bonus,
		# Module-owned: no core baseline, so the body module defines them outright.
		BodyStats.CARRY_CAPACITY: (bone_density * 10.0 + muscle_fiber * 5.0) * shaped,
		BodyStats.REGENERATION: organ_vitality * 0.3 * shaped,
		BodyStats.BODY_CULTIVATION_POWER:
		(bone_density + muscle_fiber + organ_vitality) * 0.5 * shaped,
	}


## The realm factor, or neutral when the path is unstarted. An unknown realm id
## resolves to neutral inside the profile class, so a path holding a stale rank
## degrades instead of throwing.
func _realm_factor(context: StatContext) -> float:
	var state := context.path(BodyPath.PATH_ID)
	if state == null:
		return BodyRealmProfile.NEUTRAL
	return BodyRealmProfile.factor(state.rank_id)


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
