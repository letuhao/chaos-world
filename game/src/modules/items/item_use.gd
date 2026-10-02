class_name ItemUse
extends RefCounted

## The consumed / learned activation consumers (ADR 0028). One hook for every
## non-equipment category so fixed and rolled options always have a real effect:
##   - consumable: one-shot resource restoration, never a permanent modifier
##   - technique: permanent base-attribute gains from studying the item
##   - key/currency/quest/misc: craft-catalyst properties consumed by Crafting
## Nothing applies merely because an item is held.


## Preview what using `instance` would do. Never consumes, never mutates, and
## never advances the roll stream, so UI can show outcomes before committing.
static func preview(def: ItemDef, instance: ItemInstance) -> Dictionary:
	var effects := ItemEffects.resolve(def, instance)
	var restorations := ItemEffects.resource_restorations(effects)
	var stat_gains := _base_gains(effects)
	return {
		"activation": def.activation(),
		"restores": restorations,
		"stat_gains": stat_gains,
		"craft_potency": ItemEffects.property_value(effects, OptionTarget.CRAFT_POTENCY),
		"lines": ItemEffects.describe(effects),
	}


## Apply `instance`'s activation to `actor` and return the outcome dictionary.
## The caller owns consumption; this never removes inventory on its own.
static func apply(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": "unknown_definition"}
	match def.activation():
		ItemActivation.CONSUMED:
			return _apply_consumed(actor, def, instance)
		ItemActivation.LEARNED:
			return _apply_learned(actor, def, instance)
		ItemActivation.PROPERTY:
			return _apply_property(def, instance)
		_:
			return {"ok": false, "reason": "not_usable"}


static func _apply_consumed(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	var effects := ItemEffects.resolve(def, instance)
	var restorations := ItemEffects.resource_restorations(effects)
	var applied := {}
	for pool_id in restorations.keys():
		var pool := actor.resource(StringName(pool_id))
		if pool == null:
			continue
		var delta := float(restorations[pool_id])
		pool.change(delta)
		applied[String(pool_id)] = delta
	# A consumable's stat targets are cultivation seed, not a permanent buff:
	# they are reported, never silently applied as a permanent modifier.
	var stat_gains := _base_gains(effects)
	if applied.is_empty() and stat_gains.is_empty():
		return {"ok": false, "reason": "no_applicable_effect"}
	actor.mark_stats_dirty()
	return {"ok": true, "restores": applied, "stat_gains": stat_gains}


static func _apply_learned(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	var gains := _base_gains(ItemEffects.resolve(def, instance))
	if gains.is_empty():
		return {"ok": false, "reason": "no_applicable_effect"}
	for stat_id in gains.keys():
		var id := StringName(stat_id)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(gains[stat_id]))
	actor.mark_stats_dirty()
	return {"ok": true, "stat_gains": gains}


static func _apply_property(def: ItemDef, instance: ItemInstance) -> Dictionary:
	var values := properties(def, instance)
	if values.is_empty():
		return {"ok": false, "reason": "no_applicable_effect"}
	return {"ok": true, "properties": values}


## Numeric item properties carried by `def`/`instance`. Read by Crafting for
## potency/yield and by ItemsApi for key reach, quest potency and trade value,
## so a property option is never decorative (ADR 0028).
static func properties(def: ItemDef, instance: ItemInstance) -> Dictionary:
	var effects := ItemEffects.resolve(def, instance)
	var out := {}
	for property_id in OptionTarget.PROPERTIES:
		var value := ItemEffects.property_value(effects, property_id)
		if value > 0.0:
			out[String(property_id)] = value
	return out


## Base-attribute gains: only true base attributes persist from a use; derived
## stats are recomputed and must not be stored (ADR 0001).
static func _base_gains(effects: Array[Dictionary]) -> Dictionary:
	var out := {}
	for effect in effects:
		if StringName(effect.get("target_type", &"")) != OptionTarget.STAT:
			continue
		if StringName(effect.get("op", &"")) != &"FLAT":
			continue
		var target := StringName(effect.get("target_id", &""))
		if not Stat.BASE_ATTRIBUTES.has(target):
			continue
		out[String(target)] = float(out.get(String(target), 0.0)) + float(effect.get("value", 0.0))
	return out
