extends TestCase

## ADR 0025/0026/0028: equipment applies an item's fixed and rolled effects
## exactly once, under its own source id, and removes them reversibly.


func _sword() -> ItemDef:
	# No roll_spec: these tests assert exact authored values. Rolled affixes are
	# covered in test_item_generator.gd.
	var def := ItemDef.new()
	def.id = &"sword"
	def.display_name = "Sword"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.WEAPON
	def.stackable = false
	def.rarity = &"rare"
	def.realm = &"qi_refining"
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 25.0}]
	return def


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	return actor


func test_equip_applies_fixed_modifier_once() -> void:
	var actor := _hero()
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 20.0, "base attack")
	var instance := ItemInstance.new(&"sword", &"sword_1")
	assert_eq(
		ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, _sword(), instance),
		true,
		"equipped"
	)
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 45.0, "equip bonus applied once")
	# Re-equipping the same instance must not accumulate a second contribution.
	ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, _sword(), instance)
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 45.0, "no drift on re-equip")


func test_unequip_removes_modifier() -> void:
	var actor := _hero()
	var equipment := ItemsApi.equipment(actor)
	equipment.equip(actor, Equipment.WEAPON, _sword(), ItemInstance.new(&"sword", &"sword_1"))
	equipment.unequip(actor, Equipment.WEAPON)
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 20.0, "bonus removed")


func test_rolled_option_applies_exactly_once() -> void:
	var actor := _hero()
	var def := _sword()
	var instance := ItemInstance.new(&"sword", &"sword_1")
	instance.rarity = &"rare"
	instance.realm = &"qi_refining"
	instance.rolled = [
		{
			"option_id": &"core_max_health",
			"target_type": &"stat",
			"target_id": &"max_health",
			"scope": &"",
			"op": &"FLAT",
			"unit": &"magnitude",
			"value": 30.0,
			"channel": &"rolled",
		}
	]
	var before := actor.stats.derived(Stat.MAX_HEALTH)
	ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, def, instance)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), before + 30.0, "rolled applied once")
	ItemsApi.equipment(actor).rebuild(actor, Equipment.WEAPON)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), before + 30.0, "rebuild does not drift")
	ItemsApi.equipment(actor).unequip(actor, Equipment.WEAPON)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), before, "rolled removed")


func test_capacity_option_does_not_refill_resource() -> void:
	var actor := _hero()
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.resource(&"health").change(-60.0)
	var def := _sword()
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 500.0}]
	# A one-shot restore is not a stat modifier, so equipment cannot apply it.
	ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, def, ItemInstance.new(&"s", &"s1"))
	assert_almost_eq(actor.resource(&"health").current, 40.0, "no refill on equip")


func test_invalid_slot_rejected() -> void:
	var actor := _hero()
	assert_eq(
		ItemsApi.equipment(actor).equip(actor, &"tail", _sword(), ItemInstance.new(&"sword", &"s")),
		false,
		"bad slot"
	)


func test_equip_rejects_non_equipment() -> void:
	var actor := _hero()
	var herb := ItemDef.new()
	herb.id = &"herb"
	herb.category = ItemCategory.MATERIAL
	assert_eq(
		ItemsApi.equipment(actor).equip(
			actor, Equipment.WEAPON, herb, ItemInstance.new(&"herb", &"h")
		),
		false,
		"material is not equipment"
	)


func test_equip_rejects_instance_def_mismatch() -> void:
	var actor := _hero()
	assert_eq(
		ItemsApi.equipment(actor).equip(
			actor, Equipment.WEAPON, _sword(), ItemInstance.new(&"other", &"o")
		),
		false,
		"instance def_id must match"
	)


func test_equip_rejects_bound_item_for_another_actor() -> void:
	var actor := _hero()
	var instance := ItemInstance.new(&"sword", &"sword_1")
	instance.bound_to = &"someone_else"
	assert_eq(
		ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, _sword(), instance),
		false,
		"bound item cannot equip elsewhere"
	)


func test_equip_rejects_grade_requirement_and_keeps_current() -> void:
	var actor := _hero()
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	var weak := _sword()
	var instance := ItemInstance.new(&"sword", &"sword_1")
	assert_eq(
		ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, weak, instance), true, "equipped"
	)
	var strong := _sword()
	strong.id = &"greatsword"
	strong.grade = ItemGrade.DIVINE
	assert_eq(
		ItemsApi.equipment(actor).equip(
			actor, Equipment.WEAPON, strong, ItemInstance.new(&"greatsword", &"g1")
		),
		false,
		"grade requirement unmet"
	)
	assert_eq(ItemsApi.equipment(actor).equipped(Equipment.WEAPON).def_id, &"sword", "current kept")


func test_equip_item_from_inventory() -> void:
	var actor := _hero()
	var sword := _sword()
	ItemsApi.inventory(actor).add(sword, 1)
	assert_eq(ItemsApi.equip_item(actor, Equipment.WEAPON, sword), true, "equipped")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 45.0, "bonus applied")
	assert_eq(ItemsApi.inventory(actor).find_instance(&"sword"), null, "left inventory")


func test_rejected_equip_leaves_item_in_inventory() -> void:
	var actor := _hero()
	var def := ItemDef.new()
	def.id = &"sword"
	def.category = ItemCategory.EQUIPMENT
	def.stackable = false
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(actor, &"tail", def), false, "bad slot rejected")
	assert_eq(ItemsApi.inventory(actor).find_instance(&"sword") != null, true, "still held")


func test_unequip_to_inventory_preserves_instance() -> void:
	var actor := _hero()
	var sword := _sword()
	ItemsApi.inventory(actor).add(sword, 1)
	ItemsApi.equip_item(actor, Equipment.WEAPON, sword)
	var instance_id := ItemsApi.equipment(actor).equipped(Equipment.WEAPON).instance_id
	assert_eq(ItemsApi.unequip_to_inventory(actor, Equipment.WEAPON), true, "unequipped")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 20.0, "bonus removed")
	var restored := ItemsApi.inventory(actor).find_instance(&"sword")
	assert_eq(restored != null, true, "back in inventory")
	assert_eq(restored.instance_id, instance_id, "same instance id")


func test_actor_save_restore_preserves_equipped_item() -> void:
	var actor := _hero()
	var def := load("res://data/items/equipment/armor_iron_helm.tres") as ItemDef
	def.stackable = false
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, def), true, "equipped")
	var expected := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_almost_eq(expected, 20.0, "helm bonus applied")
	var payload := actor.to_dict()
	assert_eq(payload.has("item_state"), true, "item state in payload")
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	assert_almost_eq(restored.stats.derived(Stat.DEFENSE_PHYSICAL), expected, "bonus after restore")
	assert_eq(
		ItemsApi.equipment(restored).equipped(Equipment.ARMOR) != null, true, "armor restored"
	)
	assert_eq(ItemsApi.unequip_to_inventory(restored, Equipment.ARMOR), true, "unequipped")
	assert_almost_eq(restored.stats.derived(Stat.DEFENSE_PHYSICAL), 15.0, "bonus removed")
	assert_eq(
		ItemsApi.inventory(restored).find_instance(&"armor_iron_helm") != null,
		true,
		"back in inventory"
	)


func test_save_restore_preserves_inventory_stacks() -> void:
	var actor := _hero()
	var ore := load("res://data/items/material/armor_iron_ore.tres") as ItemDef
	ItemsApi.inventory(actor).add(ore, 15)
	var payload := actor.to_dict()
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	assert_eq(ItemsApi.inventory(restored).count(&"armor_iron_ore"), 15, "stacks restored")
