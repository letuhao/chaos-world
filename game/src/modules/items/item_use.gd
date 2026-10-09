class_name ItemUse
extends RefCounted

## The consumed / learned activation consumers (ADR 0028). One hook for every
## non-equipment category so fixed and rolled options always have a real effect:
##   - consumable: one-shot resource restoration, never a permanent modifier
##   - technique: permanent base-attribute gains from studying the item
##   - key/currency/quest/misc: craft-catalyst properties, READ by Crafting, loot
##     and economy — never spent, so this module refuses to spend them either
## Nothing applies merely because an item is held, and nothing is DESTROYED merely
## because an item was pressed.
##
## ## The spend gate
##
## [method apply] is the one place an item can be destroyed, so it is the one place
## that decides whether destroying it is honest. Two refusals live here and both are
## named, because a refusal nobody can name is a bug report:
##
##   - `progression_input` — the item is a REQUIRED PROGRESSION INPUT
##     ([ProgressionRoles]): a realm seed names it and the path is the only thing
##     allowed to spend it. Use would apply a generic one-shot effect and delete the
##     only copy of the price of an attempt (BL-0110).
##   - `no_spend_consumer` — the item's channel has no consumer that spends it. The
##     property channel is a READ channel: `key_reach` is read by loot, `trade_value`
##     by economy, `craft_potency` by Crafting, and none of them spend the item. So
##     "using" one destroyed a key, a coin or a quest item and changed nothing at all —
##     the same destruction BL-0110 is about, on 900 more items, for less benefit.
##
## Everything below applies an EFFECT or refuses. There is no branch that returns
## `ok` while applying nothing, which is what made both defects possible.

## `def` names no definition, so there is nothing to apply.
const REASON_UNKNOWN_DEFINITION := &"unknown_definition"
## `def` is a required progression input; the path that names it spends it.
const REASON_PROGRESSION_INPUT := &"progression_input"
## `def`'s channel is read-only, so spending it would destroy it for no effect.
const REASON_NO_SPEND_CONSUMER := &"no_spend_consumer"
## `def` is spendable, but nothing it carries applies to this actor.
const REASON_NO_EFFECT := &"no_applicable_effect"
## `def`'s category has no Use verb at all — equipment and material.
const REASON_NOT_USABLE := &"not_usable"
## The `ProjectSettings` key `app/` writes the delivery seam under. A String, so
## reading it costs nothing and a build with no seam reads as "unset" rather than
## as a missing symbol.
const DELIVERY_SETTING := "technique/delivery_seam"


## Preview what using `instance` would do. Never consumes, never mutates, and
## never advances the roll stream, so UI can show outcomes before committing.
##
## `spendable` / `block_reason` / `role` are the gate's own answer rather than a
## restatement of it, so a caller that wants to grey out a control and a caller
## that presses it are told the same thing by the same code.
static func preview(def: ItemDef, instance: ItemInstance) -> Dictionary:
	var effects := ItemEffects.resolve(def, instance)
	var restorations := ItemEffects.resource_restorations(effects)
	var stat_gains := _base_gains(effects)
	var gate := spend_gate(def, instance)
	return {
		"activation": def.activation(),
		"restores": restorations,
		"stat_gains": stat_gains,
		"craft_potency": ItemEffects.property_value(effects, OptionTarget.CRAFT_POTENCY),
		"lines": ItemEffects.describe(effects),
		"spendable": gate.is_empty(),
		"block_reason": String(gate.get("reason", "")),
		"role": String(gate.get("role", "")),
	}


## Apply `instance`'s activation to `actor` and return the outcome dictionary.
## The caller owns consumption; this never removes inventory on its own.
##
## Returns a refusal — never `ok` with nothing applied — when [method spend_gate]
## refuses, and `ok` only when an effect actually landed on `actor`.
static func apply(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": REASON_UNKNOWN_DEFINITION}
	var gate := spend_gate(def, instance)
	if not gate.is_empty():
		return gate
	match def.activation():
		ItemActivation.CONSUMED:
			return _apply_consumed(actor, def, instance)
		ItemActivation.LEARNED:
			return _apply_learned(actor, def, instance)
		ItemActivation.PROPERTY:
			return _refuse_read_only(def, instance)
		_:
			return {"ok": false, "reason": REASON_NOT_USABLE}


## Why `def` may not be spent from the inventory, or `{}` when it may.
##
## Asked BEFORE any effect is resolved, so a refused spend never even reads the
## item's options — there is nothing to apply, so there is nothing to compute.
static func spend_gate(def: ItemDef, instance: ItemInstance = null) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": REASON_UNKNOWN_DEFINITION}
	var role := ProgressionRoles.role_of(def.id)
	if role != &"":
		return {"ok": false, "reason": REASON_PROGRESSION_INPUT, "role": String(role)}
	if def.activation() == ItemActivation.PROPERTY:
		return _refuse_read_only(def, instance)
	return {}


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
	# ## The cleanse lever, and why it is a REMOVAL and not a restoration
	#
	# `def.cleanse_lever` is empty on every other authored item, so this branch is
	# inert for the whole corpus until a pill names a lever. When it is named, the
	# spend is `StatusApi.cleanse(actor, lever)`: one lever in, the status module's own
	# `mitigation_tags` out, and nothing here interprets a percentage or a strength.
	# That is the whole point of ADR 0086's ONE purge vocabulary — this module says
	# WHICH lever, and `status` decides what that lever removes.
	#
	# It is applied rather than OR-ed with the restorations because a cleanse pill
	# restoring a pool is a different item, and a caller that asked "did my pill answer
	# the debuff" reads `cleansed` here and nothing else. A pill carrying BOTH lands
	# both, which is authored content and is not refused here.
	var cleansed: Dictionary = {}
	if def.cleanse_lever != &"":
		cleansed = StatusApi.cleanse(actor, def.cleanse_lever)
	# ## The foundation mend, and why it is a LIFT and not a restoration
	#
	# `def.foundation_mend` is 0.0 on every other authored item, so this branch is
	# inert for the whole corpus until a pill names an amount. When it is named, the
	# spend is `FoundationApi.mend` on the WEAKEST scar (`mend_target`): one amount in,
	# the foundation module's own realm cap out, and nothing here interprets what a
	# snapshot means. That is the cleanse lever's shape exactly — this module says
	# WHICH item, and `foundation` decides what the mend lifts.
	#
	# A mend that lifts nothing is NOT `ok`, for the same BL-0110 reason a cleanse that
	# removed nothing is not: the verb would decrement the stack and the actor would be
	# identical afterwards. The caller reads `mended` here and nothing else.
	var mended: Dictionary = {}
	if def.foundation_mend > 0.0:
		var target := FoundationApi.mend_target(actor)
		if target != &"":
			var lift := FoundationApi.mend(
				actor, target, float(def.foundation_mend), String(def.id)
			)
			if bool(lift.get("ok", false)):
				mended = lift
	# A consumable's stat targets are cultivation seed, not a permanent buff: they
	# are REPORTED, never applied as a permanent modifier (ADR 0001). So a
	# consumable whose only content is a base attribute restores nothing and applies
	# nothing -- and reporting `ok` there is BL-0110 one category over: the verb
	# decrements the stack and the actor is identical afterwards. The gains ride along
	# in the refusal so a caller can still show what the item carries.
	var stat_gains := _base_gains(effects)
	# A cleanse that removed nothing is NOT `ok` either, for the same reason BL-0110 is:
	# the verb would decrement the stack and the actor would be identical afterwards.
	# The reason names WHICH lever was spent and how many statuses it answered, so a
	# caller can tell "you were not afflicted" from "that lever answers nothing on you".
	# A mend that lifted nothing joins the same gate: an elixir spent on a record with
	# no scar below the cap must refuse rather than vanish.
	if cleansed.get("count", 0) == 0 and applied.is_empty() and mended.is_empty():
		return {
			"ok": false,
			"reason": REASON_NO_EFFECT,
			"stat_gains": stat_gains,
			"cleansed": cleansed,
			"mended": mended,
		}
	actor.mark_stats_dirty()
	return {
		"ok": true,
		"restores": applied,
		"stat_gains": stat_gains,
		"cleansed": cleansed,
		"mended": mended,
	}


## Study an item that is a technique MANUAL.
##
## A `category = &"technique"` item DELIVERS a technique (ADR 0053): the three
## states have three owners, and this one is the item's. So a technique item goes
## to the delivery seam, which the composition root binds — `app/` may depend on
## anything by construction, whereas naming a techniques class from here would be
## an UNDECLARED `items -> techniques` edge the checker cannot even see
## (`BARE_REF_UNITS` excludes `modules/*`).
##
## The seam is reached WITHOUT naming its class, through a Callable the item use
## path looks up once. `TechniqueDelivery` publishes `installed()`, which returns
## that Callable (or an unbound one), so `items` holds a `Callable` and no
## technique type. A build that never installed one refuses `no_seam` rather than
## silently falling through to the old stat-stick behaviour.
static func _apply_learned(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	if def.category == ItemCategory.TECHNIQUE:
		return _study_technique(actor, def, instance)
	var gains := _base_gains(ItemEffects.resolve(def, instance))
	if gains.is_empty():
		return {"ok": false, "reason": REASON_NO_EFFECT}
	for stat_id in gains.keys():
		var id := StringName(stat_id)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(gains[id]))
	actor.mark_stats_dirty()
	return {"ok": true, "stat_gains": gains}


## Hand a technique manual to the installed delivery seam.
##
## The seam is reached through `ProjectSettings`, which the composition root writes
## at boot. That is a genuinely undeclared-by-type hop: this file names no technique
## class, holds no `res://` path into the module, and so declares no dependency the
## `tools/arch` registry has to record. `app/` may depend on anything by construction,
## so it is the only place that can install one.
static func _study_technique(actor: Actor, def: ItemDef, instance: ItemInstance) -> Dictionary:
	# The seam travels as a CALLABLE, not as the seam object. `TechniqueDelivery` is
	# a `RefCounted` script singleton: storing it through `ProjectSettings.set_setting`
	# gives back `null`, because a plain Object is not a serialisable Variant and the
	# setting drops it. A Callable IS storable, and a Callable to a static function is
	# exactly the shape the composition root already installs elsewhere.
	if not ProjectSettings.has_setting(DELIVERY_SETTING):
		return {"ok": false, "reason": "no_seam", "id": String(def.id)}
	var seam: Variant = ProjectSettings.get_setting(DELIVERY_SETTING)
	if not (seam is Callable) or not (seam as Callable).is_valid():
		return {"ok": false, "reason": "no_seam", "id": String(def.id)}
	return (seam as Callable).call(actor, def, instance)


## Refuse a read-only channel. The numbers still ride along, because a caller
## showing the item still wants them — what it must not do is charge the player a
## key to display them.
static func _refuse_read_only(def: ItemDef, instance: ItemInstance) -> Dictionary:
	var values := properties(def, instance)
	if values.is_empty():
		return {"ok": false, "reason": REASON_NO_EFFECT}
	return {"ok": false, "reason": REASON_NO_SPEND_CONSUMER, "properties": values}


## Numeric item properties carried by `def`/`instance`. Read by Crafting for
## potency/yield, by `loot` for key reach and by `economy` for trade value, so a
## property option is never decorative (ADR 0028). Read, never spent: that is what
## [method _refuse_read_only] refuses over.
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
