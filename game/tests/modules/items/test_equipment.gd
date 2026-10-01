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
