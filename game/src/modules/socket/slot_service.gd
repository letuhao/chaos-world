class_name SlotService
extends RefCounted

## The three slot transactions — creation, imputation, insert/extract — each
## validate completely before it mutates anything, so a refusal leaves the actor
## exactly as it was (ADR 0025/0026).
##
## Nothing here rerolls. An inserted gem keeps its realization, an extracted gem
## is the same instance, and a slot's imputed effects are stored on the slot, so
## they are indifferent to what is (or is not) inserted.

const ACTION_CREATE := &"create_slot"
const ACTION_IMPUTE := &"impute_slot"
const ACTION_INSERT := &"insert_socket"
const ACTION_EXTRACT := &"extract_socket"


## Open a new socket on `parent_id` for `reagent_id`. Costs exactly one reagent
## and refuses a second slot once the item's rarity cap is reached.
static func create_slot(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, reagent_id: StringName
) -> Dictionary:
	var host := _host(actor, parent_id)
	if host == null:
		return SocketResult.refused(ACTION_CREATE, parent_id, "unknown_parent")
	if SocketPolicy.is_socket_item(host):
		return SocketResult.refused(ACTION_CREATE, parent_id, "recursive_socket")
	var reagent := SocketContent.resolve(reagent_id)
	var refusal := creation_refusal(actor, ledger, parent_id, reagent)
	if not refusal.is_empty():
		return SocketResult.refused(ACTION_CREATE, parent_id, refusal)
	var kind := _kind_of_reagent(reagent)
	var cost := SocketCosts.spend(ItemsApi.inventory(actor), _single(reagent_id))
	if cost != OK:
		return SocketResult.refused(ACTION_CREATE, parent_id, "cost_failed")
	ledger.ensure_parent(parent_id, host.id)
	ledger.append_slot(parent_id, kind)
	ledger.commit(actor)
	SocketEffects.sync(actor, ledger)
	var slots: Array = ledger.parent(parent_id).get("slots", [])
	return SocketResult.committed(
		ACTION_CREATE,
		parent_id,
		[reagent_id],
		{"index": slots.size() - 1, "kind": String(kind), "cap": SocketPolicy.slot_cap(host.rarity)}
	)


## Impute an empty slot with effects from the socket slot pool. The reagent is
## consumed once; the realized effects belong to the slot.
static func impute_slot(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int, reagent_id: StringName
) -> Dictionary:
	var host := _host(actor, parent_id)
	if host == null:
		return SocketResult.refused(ACTION_IMPUTE, parent_id, "unknown_parent")
	if SocketPolicy.is_socket_item(host):
		return SocketResult.refused(ACTION_IMPUTE, parent_id, "recursive_socket")
	var reagent := SocketContent.resolve(reagent_id)
	var refusal := imputation_refusal(actor, ledger, parent_id, index, reagent)
	if not refusal.is_empty():
		return SocketResult.refused(ACTION_IMPUTE, parent_id, refusal)
	var instance: ItemInstance = SocketOwnership.locate(actor, parent_id)["instance"]
	var rng := RandomNumberGenerator.new()
	rng.seed = _stream_seed(parent_id, index, reagent_id)
	var effects := _realize(ledger, parent_id, index, instance, rng)
	if effects.is_empty():
		return SocketResult.refused(ACTION_IMPUTE, parent_id, "imprint_cap_reached")
	var cost := SocketCosts.spend(ItemsApi.inventory(actor), _single(reagent_id))
	if cost != OK:
		return SocketResult.refused(ACTION_IMPUTE, parent_id, "cost_failed")
	ledger.add_imputed(parent_id, index, effects)
	ledger.commit(actor)
	SocketEffects.sync(actor, ledger)
	return SocketResult.committed(
		ACTION_IMPUTE, parent_id, [reagent_id], {"index": index, "imputed": effects}
	)


## Insert an owned socket item into slot `index`. Non-destructive in both
## directions: the gem's instance is moved, never copied or rerolled.
static func insert_socket(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int, gem_id: StringName
) -> Dictionary:
	var owner := SocketOwnership.locate(actor, parent_id)
	if owner.is_empty():
		return SocketResult.refused(ACTION_INSERT, parent_id, "unknown_parent")
	var slot_entry := ledger.slot(parent_id, index)
	if slot_entry.is_empty():
		return SocketResult.refused(ACTION_INSERT, parent_id, "no_slot")
	if not Dictionary(slot_entry.get("gem", {})).is_empty():
		return SocketResult.refused(ACTION_INSERT, parent_id, "slot_occupied")
	var gem_owner := SocketOwnership.locate(actor, gem_id)
	var gem := _gem_def(gem_owner)
	if gem == null:
		return SocketResult.refused(ACTION_INSERT, parent_id, "unknown_socket_item")
	if SocketPolicy.carries_sockets(gem):
		return SocketResult.refused(ACTION_INSERT, parent_id, "recursive_socket")
	var refusal := insertion_refusal(actor, ledger, parent_id, index, gem_id)
	if not refusal.is_empty():
		return SocketResult.refused(ACTION_INSERT, parent_id, refusal)
	var instance: ItemInstance = gem_owner["instance"]
	# Single ownership: the instance leaves the inventory before it is recorded in
	# the slot, so it is never visible in two places at once.
	if gem_owner.get("where", &"") == SocketOwnership.WHERE_INVENTORY:
		if ItemsApi.inventory(actor).remove_instance(gem_id) == null:
			return SocketResult.refused(ACTION_INSERT, parent_id, "not_carried")
	instance.def_ref = gem
	ledger.set_gem(parent_id, index, instance.to_dict(), ItemEffects.resolve(gem, instance))
	ledger.commit(actor)
	SocketEffects.sync(actor, ledger)
	return (
		SocketResult
		. committed(
			ACTION_INSERT,
			parent_id,
			[],
			{
				"index": index,
				"gem_instance_id": String(gem_id),
				"gem_def_id": String(instance.def_id),
			}
		)
	)


## Move an inserted gem back to the inventory. Non-destructive by default: the
## same instance returns, unrerolled, with the slot's imputation intact.
static func extract_socket(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int
) -> Dictionary:
	var owner := SocketOwnership.locate(actor, parent_id)
	if owner.is_empty():
		return SocketResult.refused(ACTION_EXTRACT, parent_id, "unknown_parent")
	var slot_entry := ledger.slot(parent_id, index)
	var gem: Dictionary = slot_entry.get("gem", {})
	if gem.is_empty():
		return SocketResult.refused(ACTION_EXTRACT, parent_id, "slot_empty")
	var instance := ItemInstance.from_dict(ItemInstance.migrate(gem))
	instance.def_ref = SocketContent.resolve(instance.def_id)
	# Confirm the destination has room before the gem leaves the slot, so a full
	# bag never loses the only copy.
	if ItemsApi.inventory(actor).add_instance(instance) != 0:
		return SocketResult.refused(ACTION_EXTRACT, parent_id, "inventory_full")
	ledger.set_gem(parent_id, index, {}, [])
	ledger.commit(actor)
	SocketEffects.sync(actor, ledger)
	return (
		SocketResult
		. committed(
			ACTION_EXTRACT,
			parent_id,
			[],
			{
				"index": index,
				"gem_instance_id": String(instance.instance_id),
				"gem_def_id": String(instance.def_id),
			}
		)
	)


## Every reason `create_slot` would refuse right now. Empty means it would commit.
static func creation_refusal(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, reagent: ItemDef
) -> String:
	if reagent == null:
		return "unknown_reagent"
	var owner := SocketOwnership.locate(actor, parent_id)
	var host := _gem_def(owner)
	if host == null:
		return "unknown_parent"
	if not SocketPolicy.meets_tier(
		SocketPolicy.tier_of(actor.realm()), SocketPolicy.tier_of(reagent.realm)
	):
		return "realm_tier_too_low"
	if SocketPolicy.slot_cap(host.rarity) <= _slot_count(ledger, parent_id):
		return "cap_reached"
	if not ItemsApi.inventory(actor).has(reagent.id):
		return "missing_cost"
	return ""


## Every reason `impute_slot` would refuse right now.
static func imputation_refusal(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int, reagent: ItemDef
) -> String:
	if reagent == null:
		return "unknown_reagent"
	if SocketOwnership.locate(actor, parent_id).is_empty():
		return "unknown_parent"
	if not SocketPolicy.meets_tier(
		SocketPolicy.tier_of(actor.realm()), SocketPolicy.tier_of(reagent.realm)
	):
		return "realm_tier_too_low"
	var slot_entry := ledger.slot(parent_id, index)
	if slot_entry.is_empty():
		return "no_slot"
	if not Dictionary(slot_entry.get("gem", {})).is_empty():
		return "slot_occupied"
	if (slot_entry.get("imputed", []) as Array).size() >= SocketPolicy.IMPRINT_CAP:
		return "imprint_cap_reached"
	if not ItemsApi.inventory(actor).has(reagent.id):
		return "missing_cost"
	return ""


## Every reason `insert_socket` would refuse right now.
static func insertion_refusal(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int, gem_id: StringName
) -> String:
	var owner := SocketOwnership.locate(actor, parent_id)
	var host := _gem_def(owner)
	if host == null:
		return "unknown_parent"
	var slot_entry := ledger.slot(parent_id, index)
	if slot_entry.is_empty():
		return "no_slot"
	if not Dictionary(slot_entry.get("gem", {})).is_empty():
		return "slot_occupied"
	var gem_owner := SocketOwnership.locate(actor, gem_id)
	var gem := _gem_def(gem_owner)
	if gem == null:
		return "unknown_socket_item"
	if not SocketPolicy.accepts_kind(
		gem, StringName(slot_entry.get("kind", SocketPolicy.KIND_ANY))
	):
		return "incompatible_slot"
	# A low-realm item cannot host a gem authored for a higher tier; the reverse
	# is fine, so an early item is never locked out of its own sockets.
	if SocketPolicy.tier_of(gem.realm) > SocketPolicy.tier_of(host.realm):
		return "incompatible_slot"
	if gem_owner.get("where", &"") == SocketOwnership.WHERE_SOCKETED:
		return "already_socketed"
	var gem_instance: ItemInstance = gem_owner.get("instance")
	if gem_instance != null and gem_instance.bound_to != &"" and gem_instance.bound_to != actor.id:
		return "bound_to_other"
	return ""


## Every reason `extract_socket` would refuse right now.
static func extraction_refusal(
	actor: Actor, ledger: SocketLedger, parent_id: StringName, index: int
) -> String:
	if SocketOwnership.locate(actor, parent_id).is_empty():
		return "unknown_parent"
	var slot_entry := ledger.slot(parent_id, index)
	var gem: Dictionary = slot_entry.get("gem", {})
	if gem.is_empty():
		return "slot_empty"
	if ItemsApi.inventory(actor).is_full():
		return "inventory_full"
	return ""


## Imputed effects realized for one slot, never colliding with an option the
## host already carries through a foreign channel or any of its slots. `index`
## is the slot being filled: its own imputed effects bound the room left.
static func _realize(
	ledger: SocketLedger,
	parent_id: StringName,
	index: int,
	instance: ItemInstance,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var realm_id := &""
	if instance != null:
		realm_id = instance.realm
	var realm_index := maxi(0, RealmDefaults.ladder().index_of(realm_id))
	var rarity := instance.rarity if instance != null else &"common"
	var rarity_index := OptionCatalog.rarity_tier(rarity)
	var used := SocketPolicy.foreign_option_ids(instance)
	var room := SocketPolicy.IMPRINT_CAP
	for other in ledger.parent(parent_id).get("slots", []):
		var imputed: Array = other.get("imputed", [])
		for effect in imputed:
			used.append(StringName(effect.get("option_id", &"")))
		if int(other.get("index", -1)) == index:
			room = SocketPolicy.IMPRINT_CAP - imputed.size()
	var effects: Array[Dictionary] = []
	for _position in room:
		var effect := SocketPools.roll(
			SocketPools.CHANNEL_SLOT, used, realm_index, rarity_index, rng
		)
		if effect.is_empty():
			break
		used.append(StringName(effect.get("option_id", &"")))
		effects.append(effect)
	return effects


## The host definition for `parent_id`, or null when the actor does not own it.
static func _host(actor: Actor, parent_id: StringName) -> ItemDef:
	return _gem_def(SocketOwnership.locate(actor, parent_id))


static func _gem_def(owner: Dictionary) -> ItemDef:
	var def = owner.get("def")
	return def as ItemDef


static func _slot_count(ledger: SocketLedger, parent_id: StringName) -> int:
	return (ledger.parent(parent_id).get("slots", []) as Array).size()


static func _imputed_total(ledger: SocketLedger, parent_id: StringName) -> int:
	var total := 0
	for slot_entry in ledger.parent(parent_id).get("slots", []):
		total += (slot_entry.get("imputed", []) as Array).size()
	return total


## A slot's kind is the kind its creating reagent was sold in, so a player
## chooses the kind of socket they are opening.
static func _kind_of_reagent(reagent: ItemDef) -> StringName:
	var kind := SocketPolicy.kind_of(reagent)
	if SocketPolicy.KINDS.has(kind):
		return kind
	return SocketPolicy.KIND_ANY


static func _single(reagent_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(reagent_id)
	return out


static func _stream_seed(parent_id: StringName, index: int, reagent_id: StringName) -> int:
	return absi(hash("%s:%d:%s" % [parent_id, index, reagent_id])) % 2147483647
