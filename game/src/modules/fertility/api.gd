class_name FertilityApi
extends RefCounted

## Public facade for the `fertility` module. Depends on `dual_cultivation` for the
## shared fertility/potency attributes (ADR 0002).
##
## Conception -> gestation -> birth is a status machine on the actor:
## NONE -> CONCEIVED -> GESTATING -> LABOR -> POSTPARTUM -> NONE.


static func attach(actor: Actor, species: SpeciesDef = null) -> void:
	actor.stats.add_provider(FertilityProvider.new())
	if species != null:
		actor.stats.set_base(
			DualCultivationApi.FERTILITY,
			actor.stats.get_base(DualCultivationApi.FERTILITY) + species.base_fertility
		)
		actor.stats.set_base(
			DualCultivationApi.POTENCY,
			actor.stats.get_base(DualCultivationApi.POTENCY) + species.base_potency
		)


static func conception_chance(actor: Actor, partner: Actor) -> float:
	var base := actor.stats.derived(FertilityStats.CONCEPTION_CHANCE)
	var partner_factor := 1.0
	if partner != null:
		partner_factor = 1.0 + partner.stats.get_base(DualCultivationApi.POTENCY) * 0.02
	return clampf(base * partner_factor, 0.0, 0.99)


static func can_conceive(actor: Actor) -> bool:
	return not actor.has_status(FertilityStats.PREGNANCY)


static func try_conceive(actor: Actor, partner: Actor, roll: float) -> bool:
	if not can_conceive(actor):
		return false
	if roll >= conception_chance(actor, partner):
		return false
	var status := PregnancyStatus.new(FertilityStats.PREGNANCY)
	status.stage = PregnancyStatus.Stage.CONCEIVED
	status.partner_id = partner.id if partner != null else &""
	status.partner_base = partner.stats.base_dict() if partner != null else {}
	actor.add_status(status)
	return true


static func advance(actor: Actor, delta: float, species: SpeciesDef = null) -> Array[Actor]:
	var status := pregnancy(actor)
	if status == null:
		return []
	match status.stage:
		PregnancyStatus.Stage.CONCEIVED:
			status.stage = PregnancyStatus.Stage.GESTATING
		PregnancyStatus.Stage.GESTATING:
			status.progress += _gestation_step(actor, delta, species)
			if status.progress >= 1.0:
				status.stage = PregnancyStatus.Stage.LABOR
		PregnancyStatus.Stage.LABOR:
			var born := _resolve_labor(actor, status)
			status.offspring = born
			status.stage = PregnancyStatus.Stage.POSTPARTUM
			status.recovery_remaining = _recovery_time(actor)
			return born
		PregnancyStatus.Stage.POSTPARTUM:
			status.recovery_remaining -= delta * actor.stats.derived(FertilityStats.RECOVERY_RATE)
			if status.recovery_remaining <= 0.0:
				actor.statuses.erase(status)
	return []


static func pregnancy(actor: Actor) -> PregnancyStatus:
	for status in actor.statuses:
		if status is PregnancyStatus and status.id == FertilityStats.PREGNANCY:
			return status
	return null


static func roll_offspring_count(actor: Actor, roll: float) -> int:
	return 2 if roll < actor.stats.derived(FertilityStats.MULTIPLE_BIRTH_CHANCE) else 1


static func inherit_base(parent_a: Actor, parent_b: Actor, quality: float) -> Dictionary:
	var b_base := {} if parent_b == null else parent_b.stats.base_dict()
	return _combine(parent_a.stats.base_dict(), b_base, quality)


static func _combine(a_base: Dictionary, b_base: Dictionary, quality: float) -> Dictionary:
	var out := {}
	for id in a_base.keys():
		var a := float(a_base[id])
		var b := float(b_base.get(id, 0.0))
		out[id] = maxf(0.0, (a + b) * 0.5 * quality)
	for id in b_base.keys():
		if not out.has(id):
			out[id] = maxf(0.0, float(b_base[id]) * 0.5 * quality)
	return out


static func _gestation_step(actor: Actor, delta: float, species: SpeciesDef) -> float:
	var days := 30.0 if species == null else species.gestation_days
	if days <= 0.0:
		return 1.0
	return actor.stats.derived(FertilityStats.GESTATION_SPEED) * delta / days


static func _recovery_time(actor: Actor) -> float:
	return 10.0 / maxf(0.1, actor.stats.derived(FertilityStats.RECOVERY_RATE))


static func _resolve_labor(actor: Actor, status: PregnancyStatus) -> Array[Actor]:
	var quality := actor.stats.derived(FertilityStats.OFFSPRING_QUALITY)
	var base := _combine(actor.stats.base_dict(), status.partner_base, quality)
	var child := Actor.new(StringName("%s_offspring" % actor.id), base)
	child.faction = actor.faction
	var born: Array[Actor] = [child]
	return born
