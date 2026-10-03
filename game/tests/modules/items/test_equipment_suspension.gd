extends TestCase

## ADR 0052, rule 2 read from the write path. Upkeep SUSPENDS an item: it stays
## equipped and contributes nothing. test_item_requirements.gd proves that from the
## reader's side (effects() is empty); these two tests prove the WRITER agrees.
##
## effects() and rebuild() are the same statement about a slot expressed twice, so
## they must not drift apart. When they do, the suspension is silently undone the
## moment anything rebuilds the slot — which is exactly what a tick scheduler does
## when upkeep settles. DEF-0088 was that drift, in rebuild(); equip() had it too.

const WEAPON := Equipment.WEAPON


func _actor() -> Actor:
	var actor := Actor.new(&"wielder", {Stat.PHYSIQUE: 10.0, Stat.WILL: 10.0, Stat.SPIRIT: 10.0})
	ItemsApi.attach(actor, 50)
	var pool := ResourcePool.new(&"qi", 1000.0)
	pool.current = 100.0
	actor.add_resource(pool)
	# An unrelated contributor, so "no modifiers from the item" is a statement about
	# the item rather than about a stat stack that happens to be empty.
	actor.stats.add_modifier(StatModifier.new(Stat.ATTACK_PHYSICAL, Stat.Op.FLAT, 5.0, &"gift"))
	return actor


## An upkeep item that also grants a stat. Rarity and realm are set because the
## option catalogue scales magnitudes by them.
func _upkeep_item(id: StringName = &"costly_relic") -> ItemDef:
	var requirement := ItemRequirement.new()
	requirement.upkeep = {&"qi": 10.0}
	requirement.upkeep_reserve = {&"qi": 5.0}
	requirement.upkeep_interval = 60.0
	var def := ItemDef.new()
	def.id = id
	def.grade = ItemGrade.MORTAL
	def.category = ItemCategory.EQUIPMENT
	def.rarity = &"rare"
	def.realm = &"qi_refining"
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 25.0}]
	def.requirement = requirement
	return def


func _suspended(actor: Actor) -> Equipment:
	var def := _upkeep_item()
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	assert_eq(ItemsApi.equip_item(actor, WEAPON, def), true, "equips while affordable")
	assert_eq(actor.stats.modifier_count(), 2, "the item is contributing")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), 50.0, "base 20 + gift 5 + item 25")
	# Drain the actor so upkeep can no longer be met, then settle.
	actor.resource(&"qi").current = 1.0
	var equipment := ItemsApi.equipment(actor)
	var upkeep := EquipmentUpkeep.new()
	equipment.set_upkeep(upkeep)
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(WEAPON), true, "suspended once it cannot pay")
	return equipment


func test_rebuild_does_not_reactivate_a_suspended_slot() -> void:
	var actor := _actor()
	var equipment := _suspended(actor)

	assert_eq(equipment.rebuild(actor, WEAPON), true, "rebuild reports it handled the slot")
	assert_eq(equipment.equipped(WEAPON) != null, true, "and the item is STILL EQUIPPED")
	assert_eq(equipment.effects(WEAPON).is_empty(), true, "contributes nothing after a rebuild")
	assert_eq(actor.stats.modifier_count(), 1, "the item put nothing back on the stat stack")
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL), 25.0, "and the bonus is genuinely gone"
	)


func test_equipping_into_a_suspended_slot_stays_inert() -> void:
	var actor := _actor()
	var equipment := _suspended(actor)

	# An unaffordable upkeep must never BLOCK an equip (rule 2), so this succeeds.
	var incoming := _upkeep_item(&"incoming_relic")
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(incoming.id))
	assert_eq(ItemsApi.equip_item(actor, WEAPON, incoming), true, "the equip is not blocked")
	assert_eq(equipment.equipped(WEAPON).def_id, incoming.id, "the new item is equipped")
	assert_eq(equipment.effects(WEAPON).is_empty(), true, "but contributes nothing")
	assert_eq(actor.stats.modifier_count(), 1, "and adds no modifiers of its own")
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL), 25.0, "the outgoing bonus is gone too"
	)
