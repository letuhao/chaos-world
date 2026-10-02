class_name Inventory
extends RefCounted

## Slot-based inventory with stacking (ADR 0007). Observable: mutations emit
## `changed` so stat caches and UI refresh. Roll-bearing stackables merge only
## when their full stacking signature matches, so a realized roll is never lost
## to a naive merge (ADR 0025). Non-stackable items stay distinct instances.

signal changed

var capacity: int
var _stacks: Array[ItemStack] = []
## Non-stackable items (equipment, socket items) keep their own ItemInstance
## identity so rolls, sockets, and binding survive an inventory round trip.
var _instances: Array[ItemInstance] = []
var _next_id: int = 1


func _init(p_capacity: int = 24) -> void:
	capacity = maxi(1, p_capacity)


func stacks() -> Array[ItemStack]:
	return _stacks.duplicate()


func instances() -> Array[ItemInstance]:
	return _instances.duplicate()


func used_slots() -> int:
	return _stacks.size() + _instances.size()


func is_full() -> bool:
	return used_slots() >= capacity


func count(def_id: StringName) -> int:
	var total := 0
	for batch in _stacks:
		if batch.def_id == def_id:
			total += batch.quantity
	for instance in _instances:
		if instance.def_id == def_id:
			total += 1
	return total


func has(def_id: StringName, quantity: int = 1) -> bool:
	return count(def_id) >= quantity


func find(def_id: StringName) -> ItemStack:
	for batch in _stacks:
		if batch.def_id == def_id:
			return batch
	return null


## Add `quantity` units of `def`. Returns the leftover that did not fit.
func add(def: ItemDef, quantity: int) -> int:
	if def == null:
		return maxi(0, quantity)
	var requested := maxi(0, quantity)
	var remaining := requested
	if def.stackable:
		remaining = _add_batch(def, remaining)
	else:
		remaining = _add_instances(def, remaining)
	if remaining < requested:
		changed.emit()
	return remaining


func _add_batch(def: ItemDef, remaining: int) -> int:
	# A roll-bearing definition gets one realization per batch; merging only
	# happens between batches whose signature already matches.
	var prototype := _roll_instance(def)
	while remaining > 0:
		var merged := false
		for batch in _stacks:
			if batch.def_id != def.id or batch.quantity >= def.max_stack:
				continue
			if batch.signature() != prototype.signature():
				continue
			var moved := mini(def.max_stack - batch.quantity, remaining)
			batch.quantity += moved
			remaining -= moved
			merged = true
			if remaining <= 0:
				break
		if merged:
			continue
		if _stacks.size() >= capacity:
			return remaining
		var chunk := mini(def.max_stack, remaining)
		var batch := ItemStack.from_instance(prototype, chunk)
		_stacks.append(batch)
		remaining -= chunk
	return remaining


func _add_instances(def: ItemDef, remaining: int) -> int:
	while remaining > 0 and used_slots() < capacity:
		_instances.append(_roll_instance(def))
		remaining -= 1
	return remaining


func _roll_instance(def: ItemDef) -> ItemInstance:
	var instance_id := &"%s_%d" % [def.id, next_instance_id()]
	var instance := ItemInstance.new(def.id, instance_id)
	instance.def_ref = def
	instance.rarity = ItemRarity.sanitize(def.rarity)
	instance.realm = def.realm
	if def.roll_spec.is_empty():
		return instance
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var realized := ItemGenerator.generate(def, instance_id, rng)
	realized.def_ref = def
	return realized


## The authored definition for a carried item id, preferring the live reference
## the inventory kept and falling back to the content tree.
func definition_of(def_id: StringName) -> ItemDef:
	for instance in _instances:
		if instance.def_id == def_id and instance.def_ref != null:
			return instance.def_ref
	for batch in _stacks:
		if batch.def_id == def_id and batch.def_ref != null:
			return batch.def_ref
	return null


func remove(def_id: StringName, quantity: int) -> int:
	var remaining := maxi(0, quantity)
	var removed := 0
	var kept: Array[ItemStack] = []
	for batch in _stacks:
		if batch.def_id == def_id and remaining > 0:
			var taken := mini(batch.quantity, remaining)
			batch.quantity -= taken
			remaining -= taken
			removed += taken
		if batch.quantity > 0:
			kept.append(batch)
	_stacks = kept
	var kept_instances: Array[ItemInstance] = []
	for instance in _instances:
		if instance.def_id == def_id and remaining > 0:
			remaining -= 1
			removed += 1
		else:
			kept_instances.append(instance)
	_instances = kept_instances
	if removed > 0:
		changed.emit()
	return removed


func find_instance(def_id: StringName) -> ItemInstance:
	for instance in _instances:
		if instance.def_id == def_id:
			return instance
	return null


func has_instance(def_id: StringName) -> bool:
	return find_instance(def_id) != null


## The realized sample for `def_id`, preferring a distinct instance and falling
## back to a stack batch so stacked consumables still resolve their effects.
func sample(def_id: StringName) -> ItemInstance:
	var instance := find_instance(def_id)
	if instance != null:
		return instance
	var batch := find(def_id)
	if batch == null:
		return null
	var payload := batch.to_dict()
	payload["instance_id"] = "%s_sample" % batch.def_id
	var unit := ItemInstance.from_dict(payload)
	unit.def_ref = batch.def_ref
	return unit


func remove_instance(instance_id: StringName) -> ItemInstance:
	for i in _instances.size():
		if _instances[i].instance_id == instance_id:
			var instance := _instances[i]
			_instances.remove_at(i)
			changed.emit()
			return instance
	return null


## Drop every stack and instance. Used by a workbench reset and by tests that
## need a known-empty starting state; emits `changed` only when something went.
func clear() -> void:
	if _stacks.is_empty() and _instances.is_empty():
		return
	_stacks.clear()
	_instances.clear()
	changed.emit()


## Reserve the next stable instance id. Exposed so a generator can mint an id
## without reaching into the inventory's private counter.
func next_instance_id() -> int:
	_next_id += 1
	return _next_id


## Add an existing instance back (e.g. after unequip). Returns leftover.
func add_instance(instance: ItemInstance) -> int:
	if instance == null or is_full():
		return 1
	_instances.append(instance)
	changed.emit()
	return 0


## Add an existing batch back (e.g. a withdrawn reward). Returns leftover.
func add_batch(batch: ItemStack) -> int:
	if batch == null:
		return 1
	if batch.quantity <= 0:
		return 0
	if find(batch.def_id) == null and _stacks.size() >= capacity:
		return batch.quantity
	_stacks.append(batch)
	changed.emit()
	return 0


## A detached copy used to plan a transaction before mutating anything.
func snapshot() -> Inventory:
	var copy := Inventory.new(capacity)
	copy._stacks = _stacks.duplicate()
	copy._instances = _instances.duplicate()
	copy._next_id = _next_id
	return copy
