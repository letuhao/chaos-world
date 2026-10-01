extends TestCase

## ADR 0007: inventory stacking, capacity, and removal.


func _def(id: StringName, stackable: bool, max_stack: int) -> ItemDef:
	var def := ItemDef.new()
	def.id = id
	def.stackable = stackable
	def.max_stack = max_stack
	return def


func test_add_stacks_to_max() -> void:
	var inventory := Inventory.new(4)
	var herb := _def(&"herb", true, 10)
	assert_eq(inventory.add(herb, 25), 0, "all added")
	assert_eq(inventory.count(&"herb"), 25, "count")
	assert_eq(inventory.used_slots(), 3, "three stacks")


func test_add_overflows_when_full() -> void:
	var inventory := Inventory.new(2)
	var herb := _def(&"herb", true, 10)
	assert_eq(inventory.add(herb, 50), 30, "leftover")
	assert_eq(inventory.count(&"herb"), 20, "only two slots")


func test_non_stackable_uses_one_slot_each() -> void:
	var inventory := Inventory.new(5)
	var sword := _def(&"sword", false, 1)
	assert_eq(inventory.add(sword, 3), 0, "added")
	assert_eq(inventory.used_slots(), 3, "three slots")


func test_remove_and_has() -> void:
	var inventory := Inventory.new(4)
	var herb := _def(&"herb", true, 10)
	inventory.add(herb, 25)
	assert_eq(inventory.remove(&"herb", 15), 15, "removed")
	assert_eq(inventory.count(&"herb"), 10, "remaining")
	assert_eq(inventory.has(&"herb", 10), true, "has enough")
	assert_eq(inventory.has(&"herb", 11), false, "not enough")
