class_name Inventory
extends RefCounted

## Slot-based inventory with stacking (ADR 0007). Observable: mutations emit
## `changed` so stat caches and UI refresh.

signal changed

var capacity: int
var _stacks: Array[ItemStack] = []
## Non-stackable items (equipment) keep their own ItemInstance identity so
## rolls, sockets, and binding survive a inventory round trip (ADR 0007/0025).
var _instances: Array[ItemInstance] = []
var _next_id: int = 1


func _init(p_capacity: int = 24) -> void:
	capacity = maxi(1, p_capacity)


func stacks() -> Array[ItemStack]:
	return _stacks.duplicate()


func used_slots() -> int:
	return _stacks.size() + _instances.size()


func is_full() -> bool:
	return _stacks.size() + _instances.size() >= capacity


func count(def_id: StringName) -> int:
	var total := 0
	for stack in _stacks:
		if stack.def_id == def_id:
			total += stack.quantity
	for instance in _instances:
		if instance.def_id == def_id:
			total += 1
	return total


func has(def_id: StringName, quantity: int = 1) -> bool:
	return count(def_id) >= quantity


func find(def_id: StringName) -> ItemStack:
	for stack in _stacks:
		if stack.def_id == def_id:
			return stack
	return null


func add(def: ItemDef, quantity: int) -> int:
	## Returns the leftover quantity that did not fit (0 = fully added).
	var requested := maxi(0, quantity)
	var remaining := requested
	if def.stackable:
		for stack in _stacks:
			if stack.def_id != def.id or stack.quantity >= def.max_stack:
				continue
			var moved := mini(def.max_stack - stack.quantity, remaining)
			stack.quantity += moved
			remaining -= moved
			if remaining <= 0:
				break
		while remaining > 0 and _stacks.size() < capacity:
			var chunk := mini(def.max_stack, remaining)
			_stacks.append(ItemStack.new(def.id, chunk))
			remaining -= chunk
	else:
		# Non-stackable: each unit is a distinct ItemInstance with its own id.
		while remaining > 0 and used_slots() < capacity:
			_instances.append(_new_instance(def.id))
			remaining -= 1
	if remaining < requested:
		changed.emit()
	return remaining


func _new_instance(def_id: StringName) -> ItemInstance:
	var instance := ItemInstance.new(def_id, &"%s_%d" % [def_id, _next_id])
	_next_id += 1
	return instance


func remove(def_id: StringName, quantity: int) -> int:
	## Returns the quantity actually removed.
	var remaining := maxi(0, quantity)
	var removed := 0
	var kept: Array[ItemStack] = []
	for stack in _stacks:
		if stack.def_id == def_id and remaining > 0:
			var taken := mini(stack.quantity, remaining)
			stack.quantity -= taken
			remaining -= taken
			removed += taken
		if stack.quantity > 0:
			kept.append(stack)
	_stacks = kept
	# Non-stackable instances are removed one per unit.
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


func instances() -> Array[ItemInstance]:
	return _instances.duplicate()


func find_instance(def_id: StringName) -> ItemInstance:
	for instance in _instances:
		if instance.def_id == def_id:
			return instance
	return null


func has_instance(def_id: StringName) -> bool:
	return find_instance(def_id) != null


func remove_instance(instance_id: StringName) -> ItemInstance:
	for i in _instances.size():
		if _instances[i].instance_id == instance_id:
			var instance := _instances[i]
			_instances.remove_at(i)
			changed.emit()
			return instance
	return null


## Add an existing instance back (e.g. after unequip). Returns leftover (0 = added).
func add_instance(instance: ItemInstance) -> int:
	if is_full():
		return 1
	_instances.append(instance)
	changed.emit()
	return 0
