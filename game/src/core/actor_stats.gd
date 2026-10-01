class_name ActorStats
extends RefCounted

## Base attributes plus a source-tagged modifier stack. Derived stats are recomputed
## from base + modifiers and never stored as truth (ADR 0001).

var _base: Dictionary = {}
var _modifiers: Array[StatModifier] = []
var _derived: Dictionary = {}
var _dirty: bool = true


func _init(base: Dictionary = {}) -> void:
	for id in Stat.BASE_ATTRIBUTES:
		_base[id] = float(base.get(id, 0.0))
	for key in base.keys():
		_base[key] = float(base[key])


func get_base(id: StringName) -> float:
	return float(_base.get(id, 0.0))


func set_base(id: StringName, value: float) -> void:
	_base[id] = value
	_dirty = true


func base_dict() -> Dictionary:
	return _base.duplicate()


func add_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	_dirty = true


func remove_modifiers_from(source: StringName) -> void:
	var kept: Array[StatModifier] = []
	for modifier in _modifiers:
		if modifier.source != source:
			kept.append(modifier)
	_modifiers = kept
	_dirty = true


func modifier_count() -> int:
	return _modifiers.size()


func derived(id: StringName) -> float:
	_ensure()
	return float(_derived.get(id, 0.0))


func derived_all() -> Dictionary:
	_ensure()
	return _derived.duplicate()


func _ensure() -> void:
	if _dirty:
		_recompute()
		_dirty = false


func _recompute() -> void:
	_derived.clear()
	var flat := {}
	var percent := {}
	var mult := {}
	for modifier in _modifiers:
		match modifier.op:
			Stat.Op.FLAT:
				flat[modifier.stat] = float(flat.get(modifier.stat, 0.0)) + modifier.value
			Stat.Op.PERCENT:
				percent[modifier.stat] = float(percent.get(modifier.stat, 0.0)) + modifier.value
			Stat.Op.MULT:
				mult[modifier.stat] = float(mult.get(modifier.stat, 1.0)) * modifier.value

	var physique := get_base(Stat.PHYSIQUE)
	var spirit := get_base(Stat.SPIRIT)
	var aptitude := get_base(Stat.APTITUDE)
	var comprehension := get_base(Stat.COMPREHENSION)
	var agility := get_base(Stat.AGILITY)
	var will := get_base(Stat.WILL)
	var fortune := get_base(Stat.FORTUNE)

	_put(Stat.MAX_HEALTH, 50.0 + physique * 10.0, flat, percent, mult)
	_put(Stat.MAX_QI, 20.0 + spirit * 6.0 + aptitude * 8.0, flat, percent, mult)
	_put(Stat.MAX_STAMINA, 100.0 + physique + agility * 2.0, flat, percent, mult)
	_put(Stat.HEALTH_REGEN, physique * 0.1, flat, percent, mult)
	_put(Stat.QI_REGEN, aptitude * 0.2 + spirit * 0.1, flat, percent, mult)
	_put(Stat.STAMINA_REGEN, 10.0 + agility * 0.5, flat, percent, mult)
	_put(Stat.ATTACK_PHYSICAL, physique * 2.0, flat, percent, mult)
	_put(Stat.ATTACK_SPIRITUAL, spirit * 2.0 + aptitude * 0.5, flat, percent, mult)
	_put(
		Stat.CRIT_CHANCE, minf(0.75, 0.05 + fortune * 0.002 + agility * 0.0005), flat, percent, mult
	)
	_put(Stat.CRIT_DAMAGE, 1.5 + comprehension * 0.004, flat, percent, mult)
	_put(Stat.PENETRATION, spirit * 0.5, flat, percent, mult)
	_put(Stat.ATTACK_SPEED, minf(2.5, 1.0 + agility * 0.008), flat, percent, mult)
	_put(Stat.DEFENSE_PHYSICAL, physique * 1.5, flat, percent, mult)
	_put(Stat.DEFENSE_SPIRITUAL, spirit * 1.2 + will * 0.6, flat, percent, mult)
	_put(Stat.EVASION, minf(0.6, agility * 0.0015), flat, percent, mult)
	_put(Stat.POISE, physique * 0.5 + will * 0.5, flat, percent, mult)
	_put(Stat.STATUS_RESISTANCE, minf(0.8, will * 0.003), flat, percent, mult)
	_put(Stat.MOVE_SPEED, 100.0 + agility * 2.0, flat, percent, mult)
	_put(Stat.CULTIVATION_RATE, 1.0 + aptitude * 0.02, flat, percent, mult)
	_put(Stat.QI_ABSORPTION, aptitude * 0.5 + spirit * 0.2, flat, percent, mult)
	_put(Stat.BREAKTHROUGH_CHANCE, 0.1 + comprehension * 0.01 + will * 0.005, flat, percent, mult)
	_put(Stat.DAO_HEART, will, flat, percent, mult)
	_put(Stat.INSIGHT_GAIN, 1.0 + comprehension * 0.01, flat, percent, mult)
	_put(Stat.LOOT_BONUS, fortune * 0.01, flat, percent, mult)
	_put(Stat.COOLDOWN_REDUCTION, minf(0.4, comprehension * 0.002), flat, percent, mult)
	_put(Stat.QI_COST_REDUCTION, minf(0.5, aptitude * 0.001), flat, percent, mult)
	_put(Stat.DAMAGE_REDUCTION, 0.0, flat, percent, mult)


func _put(
	id: StringName, base_value: float, flat: Dictionary, percent: Dictionary, mult: Dictionary
) -> void:
	var value := (base_value + float(flat.get(id, 0.0))) * (1.0 + float(percent.get(id, 0.0)))
	value *= float(mult.get(id, 1.0))
	_derived[id] = maxf(0.0, value)
