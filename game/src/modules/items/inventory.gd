class_name Inventory
extends RefCounted

## Slot-based inventory with stacking (ADR 0007). Observable: mutations emit
## `changed` so stat caches and UI refresh.

signal changed

var capacity: int
var _stacks: Array[ItemStack] = []


func _init(p_capacity: int = 24) -> void:
	capacity = maxi(1, p_capacity)


func stacks() -> Array[ItemStack]:
	return _stacks.duplicate()


func used_slots() -> int:
	return _stacks.size()


func is_full() -> bool:
	return _stacks.size() >= capacity


func count(def_id: StringName) -> int:
	var total := 0
	for stack in _stacks:
		if stack.def_id == def_id:
			total += stack.quantity
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
		var chunk := 1 if not def.stackable else mini(def.max_stack, remaining)
		_stacks.append(ItemStack.new(def.id, chunk))
		remaining -= chunk
	if remaining < requested:
		changed.emit()
	return remaining


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
	if removed > 0:
		changed.emit()
	return removed
