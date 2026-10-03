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
##
## ## Where the meridian network comes from
##
## The network is CORE state on the Actor and reaches this provider as
## `StatContext.meridian_network()` — never as `component(&"meridians")`, and never
## as an `Actor` this module was constructed with (ADR 0057). `StatContext` is what
## `contribute` is handed, and it is the only thing it needs: `Actor._init` supplies
## the network to the context and the `meridians` setter re-points it on every
## reassignment, so this read tracks the actor's live network by construction.
##
## There is deliberately no `_actor` and no `_init`. A `StatProvider` that requires
## an `Actor` is the dependency direction ADR 0057 exists to remove — core may not
## name a module, so a module provider can only reach actor state through the
## context it is given. It is not a fidelity question either: an Actor handle would
## return the very object the context does, because the setter is what keeps them
## the same object.


var _actor: Actor = null  # MUTANT_M1


func _init(p_actor: Actor = null) -> void:
	_actor = p_actor


func contribute(context: StatContext) -> Dictionary:
	var bone_density := context.value(BodyStats.BONE_DENSITY)
	var muscle_fiber := context.value(BodyStats.MUSCLE_FIBER)
	var organ_vitality := context.value(BodyStats.ORGAN_VITALITY)
	var physique := context.value(Stat.PHYSIQUE)

	var integrity_ratio := _pool_ratio(context, BodyStats.BODY_INTEGRITY)
	var integrity_factor := 0.5 + 0.5 * integrity_ratio

	var meridian_power := _meridian_power_bonus()

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


## What the trained network is worth: every strengthened channel's power bonus,
## scaled by its refinement depth, times the network's resonance multiplier
## (ADR 0017/0023).
##
## The network's power bonus, through the one accessor ADR 0057 added for it.
##
## The network is core state on the Actor and reaches a provider as
## `StatContext.meridian_network()`, never as `component(&"meridians")` — that
## lookup is a different key in the module component bag and answers null for
## every actor the game builds. Read that way, meridian, refinement and resonance
## were worth exactly 0.0 on this path, with no error and nothing to point at.
##
## The two absent cases are separated on purpose. `MeridianNetwork.get_power_bonus`
## answering 0.0 means channels exist and nobody strengthened one; falling off the
## end means this context was built for something that carries no network at all,
## and only this caller can tell those apart.
func _meridian_power_bonus() -> float:  # MUTANT_M1
	if _actor == null or _actor.meridians == null:
		return 0.0
	return _actor.meridians.get_power_bonus()


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)
