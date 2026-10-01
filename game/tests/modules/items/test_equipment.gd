extends TestCase

## ADR 0007: equipment applies stat modifiers and invalidates the stat cache.


func _sword() -> ItemDef:
	var def := ItemDef.new()
	def.id = &"sword"
	def.category = ItemCategory.EQUIPMENT
	def.stackable = false
	def.flat_modifiers = {String(Stat.ATTACK_PHYSICAL): 25.0}
	return def


func test_equip_applies_modifier() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 20.0, "base attack")
	var instance := ItemInstance.new(&"sword", &"sword_1")
	var slot := Equipment.WEAPON
	assert_eq(ItemsApi.equipment(actor).equip(actor, slot, _sword(), instance), true, "equipped")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 45.0, "equip bonus")


func test_unequip_removes_modifier() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	var equipment := ItemsApi.equipment(actor)
	equipment.equip(actor, Equipment.WEAPON, _sword(), ItemInstance.new(&"sword", &"sword_1"))
	equipment.unequip(actor, Equipment.WEAPON)
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 20.0, "bonus removed")


func test_invalid_slot_rejected() -> void:
	var actor := Actor.new(&"hero")
	ItemsApi.attach(actor)
	var ok := ItemsApi.equipment(actor).equip(
		actor, &"tail", _sword(), ItemInstance.new(&"sword", &"s")
	)
	assert_eq(ok, false, "bad slot")


func test_equip_rejects_non_equipment() -> void:
	var actor := Actor.new(&"hero")
	ItemsApi.attach(actor)
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
	var actor := Actor.new(&"hero")
	ItemsApi.attach(actor)
	assert_eq(
		ItemsApi.equipment(actor).equip(
			actor, Equipment.WEAPON, _sword(), ItemInstance.new(&"other", &"o")
		),
		false,
		"instance def_id must match"
	)


func test_equip_item_from_inventory() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	var sword := _sword()
	ItemsApi.inventory(actor).add(sword, 1)
	assert_eq(ItemsApi.equip_item(actor, Equipment.WEAPON, sword), true, "equipped")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 45.0, "bonus applied")
	assert_eq(ItemsApi.inventory(actor).find_instance(&"sword"), null, "left inventory")


func test_unequip_to_inventory_preserves_instance() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
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
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	var def := load("res://data/items/equipment/armor_iron_helm.tres") as ItemDef
	def.stackable = false
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, def), true, "equipped")
	# Base defense_physical = physique*1.5 = 15, +5 flat from the helm = 20.
	assert_almost_eq(actor.stats.derived(Stat.DEFENSE_PHYSICAL), 20.0, "bonus before save")
	# Save and restore into a fresh actor.
	var payload := actor.to_dict()
	assert_eq(payload.has("item_state"), true, "item state in payload")
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	assert_almost_eq(restored.stats.derived(Stat.DEFENSE_PHYSICAL), 20.0, "bonus after restore")
	assert_eq(
		ItemsApi.equipment(restored).equipped(Equipment.ARMOR) != null, true, "armor restored"
	)
	# Unequip reversibly on the restored actor.
	assert_eq(ItemsApi.unequip_to_inventory(restored, Equipment.ARMOR), true, "unequipped")
	assert_almost_eq(restored.stats.derived(Stat.DEFENSE_PHYSICAL), 15.0, "bonus removed")
	assert_eq(
		ItemsApi.inventory(restored).find_instance(&"armor_iron_helm") != null,
		true,
		"back in inventory"
	)


func test_save_restore_preserves_inventory_stacks() -> void:
	var actor := Actor.new(&"hero")
	ItemsApi.attach(actor)
	var ore := load("res://data/items/material/armor_iron_ore.tres") as ItemDef
	ItemsApi.inventory(actor).add(ore, 15)
	var payload := actor.to_dict()
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	assert_eq(ItemsApi.inventory(restored).count(&"armor_iron_ore"), 15, "stacks restored")
