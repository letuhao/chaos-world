class_name SocketEffects
extends RefCounted

## What a socket host contributes while it is worn, and how that contribution
## reaches the actor exactly once (ADR 0026).
##
## The host's own fixed and rolled options are applied by `Equipment` under the
## host's instance id. Sockets are a separate, additive source keyed
## `socket:<host instance id>`: every apply removes that source in full before
## adding it again, so inserting, extracting, re-imputing or rebuilding can
## never accumulate drift, and the two channels can never collide.

const SOURCE_PREFIX := "socket:"


## The modifier source that owns every socket contribution on one host.
static func source_for(parent_instance_id: StringName) -> StringName:
	return StringName("%s%s" % [SocketEffects.SOURCE_PREFIX, parent_instance_id])


## The full socket contribution of one host: every slot's imputed effects, the
## inserted gem's own fixed and rolled options, and the enchantment channel of
## both the host and the gem it carries. An empty slot still contributes its
## imputation; a slot with a gem contributes both. Nothing here is cached: every
## read is from the ledger, so a contribution can never drift from the state that
## produced it.
static func contribution(ledger: SocketLedger, parent_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_enchantment(ledger, parent_id))
	for slot_entry in ledger.parent(parent_id).get("slots", []):
		out.append_array(_imputed(slot_entry))
		out.append_array(_gem(slot_entry))
		out.append_array(_gem_enchantment(ledger, slot_entry))
	return out


## Replace one host's whole socket contribution. Calling this with no effects
## clears it, which is what an unequipped or emptied host needs.
static func apply(actor: Actor, parent_instance_id: StringName, effects: Array[Dictionary]) -> void:
	if actor == null or parent_instance_id == &"":
		return
	var source := source_for(parent_instance_id)
	actor.stats.remove_modifiers_from(source)
	for modifier in ItemEffects.stat_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()


## Remove one host's socket contribution entirely.
static func clear(actor: Actor, parent_instance_id: StringName) -> void:
	apply(actor, parent_instance_id, [])


## Recompute every worn host's socket contribution from scratch, and drop the
## contribution of any host that is no longer worn. Called after every socket
## mutation and on every equipment change, so the two subsystems cannot drift
## apart no matter which one moved.
static func sync(actor: Actor, ledger: SocketLedger) -> void:
	if actor == null:
		return
	var equipment := ItemsApi.equipment(actor)
	var worn := {}
	if equipment != null:
		for slot in Equipment.SLOTS:
			var instance := equipment.equipped(slot)
			if instance == null:
				continue
			worn[String(instance.instance_id)] = true
			apply(actor, instance.instance_id, contribution(ledger, instance.instance_id))
	for touched in ledger.touched_ids():
		if not worn.has(String(touched)):
			clear(actor, StringName(touched))


## The enchantment channel carried by `target_id`, if any. Read through the same
## ledger as the slots, so an enchantment follows the item it was applied to.
static func _enchantment(ledger: SocketLedger, target_id: StringName) -> Array[Dictionary]:
	var effect = ledger.channel(target_id).get("effect", {})
	if not effect is Dictionary or Dictionary(effect).is_empty():
		return []
	return [effect]


## The enchantment channel carried by the gem in one slot.
static func _gem_enchantment(ledger: SocketLedger, slot_entry: Dictionary) -> Array[Dictionary]:
	var gem: Dictionary = slot_entry.get("gem", {})
	if gem.is_empty():
		return []
	return _enchantment(ledger, StringName(gem.get("instance_id", "")))


## Imputed effects for one slot, as stored. They belong to the slot, so they read
## the ledger and never the inserted gem.
static func _imputed(slot_entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect in slot_entry.get("imputed", []):
		if effect is Dictionary:
			out.append(effect)
	return out


## The inserted gem's contribution, as realized when it was seated. It travels
## with the slot rather than being recomputed, so the answer cannot drift between
## a live session and a restored one, and the gem is never rerolled.
static func _gem(slot_entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect in slot_entry.get("gem_effects", []):
		if effect is Dictionary:
			out.append(effect)
	return out
