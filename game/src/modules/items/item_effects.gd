class_name ItemEffects
extends RefCounted

## One aggregation path for every effect channel an item carries (ADR 0028).
## Fixed (item-authored) and rolled (instance-realized) options both resolve
## through the master catalog into the same normalized effect shape, so a
## consumer applies each effect exactly once and rebuilding an item replaces the
## previous contribution instead of accumulating drift.


## Every effect an item currently carries, via the definition's own aggregation.
static func resolve(def: ItemDef, instance: ItemInstance = null) -> Array[Dictionary]:
	if def == null:
		return []
	return def.effects(instance)


## Actor stat modifiers contributed by `effects`, tagged with `source` so the
## whole contribution can be removed or replaced atomically. Resource and
## property targets are not actor stats and are skipped here.
static func stat_modifiers(effects: Array[Dictionary], source: StringName) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for effect in effects:
		if StringName(effect.get("target_type", &"")) != OptionTarget.STAT:
			continue
		(
			out
			. append(
				(
					StatModifier
					. new(
						StringName(effect.get("target_id", &"")),
						_op_for(StringName(effect.get("op", &"FLAT"))),
						float(effect.get("value", 0.0)),
						source,
					)
				)
			)
		)
	return out


## Sum of the effects targeting `property_id`. Read by Crafting (ADR 0028).
static func property_value(effects: Array[Dictionary], property_id: StringName) -> float:
	var total := 0.0
	for effect in effects:
		if _targets(effect, OptionTarget.PROPERTY, property_id):
			total += float(effect.get("value", 0.0))
	return total


## One-shot resource restoration keyed by pool id. Never a persistent modifier,
## so a consumable cannot become an equip/refill exploit (ADR 0025).
static func resource_restorations(effects: Array[Dictionary]) -> Dictionary:
	var out := {}
	for effect in effects:
		if StringName(effect.get("target_type", &"")) != OptionTarget.RESOURCE:
			continue
		if StringName(effect.get("scope", &"")) != OptionTarget.SCOPE_CURRENT:
			continue
		var pool := StringName(effect.get("target_id", &""))
		out[pool] = float(out.get(pool, 0.0)) + float(effect.get("value", 0.0))
	return out


## Persistent resource capacity/regeneration targets, expressed as the derived
## stat ActorStats already composes, so there is one composition pipeline.
static func resource_modifiers(
	effects: Array[Dictionary], source: StringName
) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for effect in effects:
		if StringName(effect.get("target_type", &"")) != OptionTarget.RESOURCE:
			continue
		var scope := StringName(effect.get("scope", &""))
		if scope != OptionTarget.SCOPE_MAXIMUM and scope != OptionTarget.SCOPE_REGEN:
			continue
		(
			out
			. append(
				(
					StatModifier
					. new(
						_resource_stat(StringName(effect.get("target_id", &"")), scope),
						Stat.Op.FLAT,
						float(effect.get("value", 0.0)),
						source,
					)
				)
			)
		)
	return out


## Readable rows for the inspection UI: channel, label and a unit-aware value.
static func describe(effects: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for effect in effects:
		var unit := StringName(effect.get("unit", &""))
		var value := float(effect.get("value", 0.0))
		var shown := "%.2f" % value if unit != &"magnitude" else "%.1f" % value
		(
			out
			. append(
				(
					"%s %s %s"
					% [
						"[fixed]" if String(effect.get("channel", "")) == "fixed" else "[rolled]",
						effect.get("label", effect.get("option_id", "")),
						shown,
					]
				)
			)
		)
	return out


static func _targets(effect: Dictionary, type_id: StringName, target_id: StringName) -> bool:
	return (
		StringName(effect.get("target_type", &"")) == type_id
		and StringName(effect.get("target_id", &"")) == target_id
	)


static func _op_for(op: StringName) -> Stat.Op:
	match op:
		&"PERCENT":
			return Stat.Op.PERCENT
		&"MULT":
			return Stat.Op.MULT
		_:
			return Stat.Op.FLAT


## Map a resource pool to the derived stat expressing its persistent
## capacity/regeneration change.
static func _resource_stat(pool_id: StringName, scope: StringName) -> StringName:
	match pool_id:
		&"health":
			return Stat.HEALTH_REGEN if scope == OptionTarget.SCOPE_REGEN else Stat.MAX_HEALTH
		&"qi":
			return Stat.QI_REGEN if scope == OptionTarget.SCOPE_REGEN else Stat.MAX_QI
		&"stamina":
			return Stat.STAMINA_REGEN if scope == OptionTarget.SCOPE_REGEN else Stat.MAX_STAMINA
		_:
			return pool_id
