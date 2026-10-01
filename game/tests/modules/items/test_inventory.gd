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


func test_non_stackable_preserves_instance_identity() -> void:
	var inventory := Inventory.new(4)
	var sword := _def(&"sword", false, 1)
	inventory.add(sword, 2)
	assert_eq(inventory.used_slots(), 2, "two instances take two slots")
	var instances := inventory.instances()
	assert_eq(instances.size(), 2, "two instances stored")
	assert_eq(instances[0].def_id, &"sword", "instance def_id")
	assert_eq(instances[1].def_id, &"sword", "instance def_id")
	assert_eq(instances[0].instance_id == instances[1].instance_id, false, "distinct instance ids")


func test_find_and_remove_instance() -> void:
	var inventory := Inventory.new(4)
	var sword := _def(&"sword", false, 1)
	inventory.add(sword, 1)
	var instance := inventory.find_instance(&"sword")
	assert_eq(instance != null, true, "found")
	var removed := inventory.remove_instance(instance.instance_id)
	assert_eq(removed != null, true, "removed and returned")
	assert_eq(removed.instance_id, instance.instance_id, "same instance")
	assert_eq(inventory.find_instance(&"sword"), null, "gone from inventory")


func test_add_instance_round_trip() -> void:
	var inventory := Inventory.new(4)
	var instance := ItemInstance.new(&"sword", &"sword_99")
	assert_eq(inventory.add_instance(instance), 0, "added")
	assert_eq(inventory.find_instance(&"sword").instance_id, &"sword_99", "preserved id")
	assert_eq(inventory.remove_instance(&"sword_99").instance_id, &"sword_99", "removed")
