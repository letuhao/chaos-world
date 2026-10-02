class_name SocketOwnership
extends RefCounted

## Where an item instance currently lives, answered through the items facade's
## public surface only. A socket parent is either still in the inventory or worn
## in an equipment slot; a gem is either in the inventory or inside a socket slot.
## Ownership is single: an instance resolves to exactly one location, which is
## what makes an insert and its matching extract symmetric.

const WHERE_INVENTORY := &"inventory"
const WHERE_EQUIPPED := &"equipped"
const WHERE_SOCKETED := &"socketed"


## Locate `instance_id` for `actor`. Returns `{where, instance, def, slot}`, with
## `instance` null when the actor does not own it.
static func locate(actor: Actor, instance_id: StringName) -> Dictionary:
	if actor == null or instance_id == &"":
		return {}
	var in_bag := _from_inventory(actor, instance_id)
	if not in_bag.is_empty():
		return in_bag
	return _from_equipment(actor, instance_id)


## Every instance the actor owns as a socket parent: carried equipment plus worn
## equipment, worn first so a screen has a stable ordering. An item that can never
## carry a socket at its rarity is not offered, so a host list has no dead rows.
static func socket_hosts(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var equipment := ItemsApi.equipment(actor)
	if equipment != null:
		for slot in Equipment.SLOTS:
			var instance := equipment.equipped(slot)
			if not _hosts_sockets(instance, equipment.definition(slot)):
				continue
			(
				out
				. append(
					{
						"instance": instance,
						"def": equipment.definition(slot),
						"equip_slot": slot,
						"where": WHERE_EQUIPPED,
					}
				)
			)
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return out
	for instance in inventory.instances():
		if not _hosts_sockets(instance, instance.def_ref):
			continue
		if _wearing(equipment, instance.instance_id):
			continue
		out.append(
			{
				"instance": instance,
				"def": instance.def_ref,
				"equip_slot": &"",
				"where": WHERE_INVENTORY
			}
		)
	return out


## Every socket item the actor owns and could insert right now.
static func owned_socket_items(actor: Actor, ledger: SocketLedger) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return out
	for instance in inventory.instances():
		var def := instance.def_ref
		if def == null:
			def = SocketContent.resolve(instance.def_id)
		if not SocketPolicy.is_socket_item(def):
			continue
		out.append({"instance": instance, "def": def})
	for parent_id in ledger.parent_ids():
		var entry := ledger.parent(StringName(parent_id))
		for slot_entry in entry.get("slots", []):
			var gem: Dictionary = slot_entry.get("gem", {})
			if gem.is_empty():
				continue
			var instance := ItemInstance.from_dict(ItemInstance.migrate(gem))
			instance.def_ref = SocketContent.resolve(instance.def_id)
			(
				out
				. append(
					{
						"instance": instance,
						"def": instance.def_ref,
						"socketed": true,
						"parent_id": String(parent_id),
						"index": int(slot_entry.get("index", 0)),
					}
				)
			)
	return out


## The equipment slot `instance_id` is worn in, or "" when it is not worn.
static func equip_slot_of(actor: Actor, instance_id: StringName) -> StringName:
	if actor == null or instance_id == &"":
		return &""
	var equipment := ItemsApi.equipment(actor)
	if equipment == null:
		return &""
	for slot in Equipment.SLOTS:
		var instance := equipment.equipped(slot)
		if instance != null and instance.instance_id == instance_id:
			return slot
	return &""


## Rebuild the live definition reference on every instance the actor owns. A
## loaded instance carries ids only, so this is what lets a restored gem resolve
## its definition without a second lookup.
static func rehydrate(actor: Actor) -> void:
	if actor == null:
		return
	var inventory := ItemsApi.inventory(actor)
	if inventory != null:
		for instance in inventory.instances():
			if instance.def_ref == null:
				instance.def_ref = SocketContent.resolve(instance.def_id)


static func _from_inventory(actor: Actor, instance_id: StringName) -> Dictionary:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return {}
	for instance in inventory.instances():
		if instance.instance_id != instance_id:
			continue
		var def := instance.def_ref
		if def == null:
			def = SocketContent.resolve(instance.def_id)
			instance.def_ref = def
		return {
			"where": WHERE_INVENTORY,
			"instance": instance,
			"def": def,
			"slot": &"",
		}
	return {}


static func _from_equipment(actor: Actor, instance_id: StringName) -> Dictionary:
	var equipment := ItemsApi.equipment(actor)
	if equipment == null:
		return {}
	for slot in Equipment.SLOTS:
		var instance := equipment.equipped(slot)
		if instance == null or instance.instance_id != instance_id:
			continue
		return {
			"where": WHERE_EQUIPPED,
			"instance": instance,
			"def": equipment.definition(slot),
			"slot": slot,
		}
	return {}


## Whether this instance is an item a socket could ever be opened on: it is
## equipment, it is not itself a socket item, and its rarity leaves room for one.
static func _hosts_sockets(instance: ItemInstance, def: ItemDef) -> bool:
	if instance == null or not SocketPolicy.carries_sockets(def):
		return false
	return SocketPolicy.slot_cap(instance.rarity) > 0


static func _wearing(equipment: Equipment, instance_id: StringName) -> bool:
	if equipment == null:
		return false
	for slot in Equipment.SLOTS:
		var instance := equipment.equipped(slot)
		if instance != null and instance.instance_id == instance_id:
			return true
	return false
