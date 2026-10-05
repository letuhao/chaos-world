extends TestCase

## ADR 0052: equipment requirements. Adapted from Keepverse's
## docs/ideas/equipment-requirement-maintenance.md.
##
## The point of the feature is that an exceptional item cannot simply be worn by a
## weak actor for free. Two rules carry that, and both are tested here because both
## are easy to break by accident:
##   1. gear never enables its own requirement
##   2. upkeep SUSPENDS an item; it never unequips and never blocks an equip

const WEAPON := Equipment.WEAPON


func _actor(base: Dictionary = {}) -> Actor:
	var stats := {Stat.PHYSIQUE: 10.0, Stat.WILL: 10.0, Stat.SPIRIT: 10.0}
	for key in base:
		stats[key] = float(base[key])
	var actor := Actor.new(&"wielder", stats)
	ItemsApi.attach(actor, 50)
	return actor


## Give the actor a path AFTER attach, which is the order the game uses.
func _at_realm(actor: Actor, realm_id: StringName) -> Actor:
	actor.set_path(PathState.new(PathState.QI, realm_id))
	return actor


func _def_with(requirement: ItemRequirement) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_relic"
	def.grade = ItemGrade.MORTAL
	def.category = ItemCategory.EQUIPMENT
	def.requirement = requirement
	return def


## Attach BEFORE the path is set: `attach` rebuilds actor state, so setting a path
## first and attaching after silently loses it, which made a requirement look
## unmet when the actor had actually arrived.
func _equip(actor: Actor, def: ItemDef) -> bool:
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor, 50)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	return ItemsApi.equip_item(actor, WEAPON, def)


# --- profiles are optional -------------------------------------------------


## Rarity does not imply demand. The overwhelmingly common case is no profile at
## all, so it must stay free of every restriction.
func test_no_profile_means_no_restriction() -> void:
	var actor := _actor()
	var def := _def_with(null)
	assert_eq(_equip(actor, def), true, "an unrestricted item equips for anyone")


func test_an_empty_profile_is_also_unrestricted() -> void:
	var actor := _actor()
	var def := _def_with(ItemRequirement.new())
	assert_eq(def.requirement.is_empty(), true, "an empty profile is empty")
	assert_eq(_equip(actor, def), true, "and equips for anyone")


# --- realm requirement -----------------------------------------------------


## The realm floor reads the one power ladder, so it is never a private
## level-to-cost curve. A relic authored at the top of the ladder is gated on the
## ladder's own top index.
## The floor is a realm ORDINAL — 0 at Qi Refining, 29 at Primordial Origin — so a
## relic authored for the top of the ladder is gated on the top realm. The ordinal
## is the ladder's own index, which is what makes this comparable without any
## conversion: the actor is at a realm, not at a number.
func test_realm_requirement_gates_on_realm_ordinal() -> void:
	var top := RealmDefaults.ladder().size() - 1
	var requirement := ItemRequirement.new()
	requirement.min_realm_index = top
	var def := _def_with(requirement)

	var weak := _at_realm(_actor(), &"qi_refining")
	assert_eq(
		RealmDefaults.ladder().index_of(&"qi_refining") < requirement.min_realm_index,
		true,
		"R1 is below"
	)
	assert_eq(_equip(weak, def), false, "a fresh R1 cannot wear a top-of-ladder relic")

	var strong := _at_realm(_actor(), &"primordial_origin")
	assert_eq(
		RealmDefaults.ladder().index_of(&"primordial_origin"),
		requirement.min_realm_index,
		"R30 is the floor"
	)
	assert_eq(_equip(strong, def), true, "a R30 actor can")


## Breakthroughs inside a realm do NOT move the floor, and that is deliberate: the
## floor names a realm, so a stage count must not make a R2 actor satisfy a R9
## demand. Asserted because the old unit (a composed index) did count them, and
## silently inheriting that would make the new unit a renaming rather than a change.
func test_breakthroughs_do_not_raise_the_actor_over_a_realm_floor() -> void:
	var requirement := ItemRequirement.new()
	# R10 (ordinal 9) is the floor; Core Formation is ordinal 2.
	requirement.min_realm_index = RealmDefaults.ladder().index_of(&"spirit_condensation")
	var def := _def_with(requirement)

	var fresh := _at_realm(_actor(), &"core_formation")
	assert_eq(
		RealmDefaults.ladder().index_of(&"core_formation") < requirement.min_realm_index,
		true,
		"R3 is below a R10 floor"
	)
	assert_eq(_equip(fresh, def), false, "a fresh R3 is refused")

	# Many breakthroughs, still ordinal 2 — the floor reads the realm, so the gate
	# still refuses rather than letting stage count buy the item.
	var veteran := _at_realm(_actor(), &"core_formation")
	veteran.path(PathState.QI).stage = 40
	assert_eq(requirement.unmet(veteran).is_empty(), false, "stage does not substitute for a realm")
	assert_eq(_equip(veteran, def), false, "and the gate still refuses")


## An actor AT the floor realm passes outright, whatever its stage.
func test_an_actor_at_the_floor_realm_passes_outright() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_realm_index = RealmDefaults.ladder().index_of(&"spirit_condensation")
	var def := _def_with(requirement)
	var actor := _at_realm(_actor(), &"spirit_condensation")
	assert_eq(requirement.unmet(actor).is_empty(), true, "exactly at the floor passes")
	assert_eq(_equip(actor, def), true, "and the item equips")


## The floor reads every path, so an item never demands one specific cultivation
## system.
func test_the_realm_floor_accepts_any_path() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_realm_index = RealmDefaults.ladder().index_of(&"spirit_sea")
	var actor := _at_realm(_actor(), &"spirit_manifestation")
	assert_eq(
		RealmDefaults.ladder().index_of(&"spirit_manifestation") >= requirement.min_realm_index,
		true,
		"a Spirit-tier realm clears it"
	)
	# The floor takes the BEST path, so a second weaker one cannot hold it back.
	actor.set_path(PathState.new(PathState.MIND, &"qi_refining"))
	assert_eq(
		RealmDefaults.ladder().index_of(&"qi_refining") >= requirement.min_realm_index,
		false,
		"the mind path alone would not clear it"
	)
	assert_eq(
		requirement.unmet(actor).is_empty(),
		true,
		"but the requirement reads the best path, so the item is wearable"
	)


# --- fixed and ratio requirements -------------------------------------------


func test_fixed_requirement_gates_on_a_base_stat() -> void:
	var requirement := ItemRequirement.new()
	requirement.fixed_minimums = {Stat.WILL: 100.0}
	var def := _def_with(requirement)
	assert_eq(_equip(_actor({Stat.WILL: 10.0}), def), false, "too weak")
	assert_eq(_equip(_actor({Stat.WILL: 150.0}), def), true, "strong enough")


## Rule 1. The ratio reads BASE allocation. If it read a derived stat, equipping
## the item would grant the very stat it demands and the requirement would be a
## no-op that always passes on the second equip.
func test_ratio_requirement_reads_base_allocation_not_derived() -> void:
	var requirement := ItemRequirement.new()
	requirement.ratio_minimums = {Stat.WILL: 0.6, Stat.PHYSIQUE: 0.0}
	var def := _def_with(requirement)

	var even := _actor({Stat.WILL: 10.0, Stat.PHYSIQUE: 10.0})
	var even_total := even.stats.get_base(Stat.WILL) + even.stats.get_base(Stat.PHYSIQUE)
	assert_eq(
		even.stats.get_base(Stat.WILL) / even_total < 0.6, true, "an even split fails the lean"
	)
	assert_eq(_equip(even, def), false, "an even build is refused")

	var leaning := _actor({Stat.WILL: 90.0, Stat.PHYSIQUE: 10.0})
	assert_eq(_equip(leaning, def), true, "a will-leaning build is accepted")


## Rule 1, stated as a regression: granting a stat as an ITEM effect must not
## satisfy a requirement on that stat. The actor's base never moves, so the ratio
## cannot be self-funded.
func test_an_item_effect_cannot_satisfy_its_own_requirement() -> void:
	var requirement := ItemRequirement.new()
	requirement.ratio_minimums = {Stat.WILL: 0.95, Stat.PHYSIQUE: 0.0}
	var def := _def_with(requirement)

	var actor := _actor({Stat.WILL: 50.0, Stat.PHYSIQUE: 50.0})
	# Give the actor a huge derived WILL without touching its base allocation.
	actor.stats.add_modifier(StatModifier.new(Stat.WILL, Stat.Op.FLAT, 10000.0, &"gift"))
	var derived_total := actor.stats.derived(Stat.WILL) + actor.stats.derived(Stat.PHYSIQUE)
	assert_eq(
		actor.stats.derived(Stat.WILL) / derived_total >= 0.95,
		true,
		"the DERIVED stat would pass the gate"
	)
	assert_eq(
		requirement.satisfied_by(actor),
		false,
		"but the requirement reads base, so it correctly refuses"
	)


func test_unmet_reports_every_problem_for_a_panel() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_realm_index = 29
	requirement.fixed_minimums = {Stat.WILL: 100.0}
	var actor := _actor({Stat.WILL: 1.0})
	var problems := requirement.unmet(actor)
	assert_eq(problems.size(), 2, "both failures are reported, not just the first")
	assert_eq(problems[0]["kind"], ItemRequirement.REALM, "realm first")
	assert_ne(String(problems[0]["label"]), "", "and it carries a human label")


# --- upkeep: suspend, never unequip -----------------------------------------


func _upkeep_item() -> ItemDef:
	var requirement := ItemRequirement.new()
	requirement.upkeep = {&"qi": 10.0}
	requirement.upkeep_reserve = {&"qi": 5.0}
	requirement.upkeep_interval = 60.0
	return _def_with(requirement)


func _qi_actor(amount: float) -> Actor:
	var actor := _actor()
	var pool := ResourcePool.new(&"qi", 1000.0)
	pool.current = amount
	actor.add_resource(pool)
	return actor


## Rule 2. An item whose upkeep cannot be paid stays EQUIPPED and contributes
## nothing. It is not unequipped, so combat spending cannot cascade a strip.
func test_unaffordable_upkeep_suspends_without_unequipping() -> void:
	var actor := _qi_actor(100.0)
	var def := _upkeep_item()
	ItemsApi.attach(actor, 50)
	var equipment := ItemsApi.equipment(actor)
	var upkeep := EquipmentUpkeep.new()
	equipment.set_upkeep(upkeep)

	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	assert_eq(ItemsApi.equip_item(actor, WEAPON, def), true, "equips while affordable")
	assert_eq(upkeep.is_suspended(WEAPON), false, "active while it can pay")

	# Drain the actor so upkeep can no longer be met.
	actor.resource(&"qi").current = 3.0
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(WEAPON), true, "suspended once it cannot pay")
	assert_eq(equipment.equipped(WEAPON) != null, true, "but STILL EQUIPPED")


## Paying again reactivates it, and the item starts contributing again.
func test_paying_again_reactivates_a_suspended_item() -> void:
	var actor := _qi_actor(100.0)
	var def := _upkeep_item()
	ItemsApi.attach(actor, 50)
	var equipment := ItemsApi.equipment(actor)
	var upkeep := EquipmentUpkeep.new()
	equipment.set_upkeep(upkeep)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	ItemsApi.equip_item(actor, WEAPON, def)

	actor.resource(&"qi").current = 1.0
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(WEAPON), true, "suspended")

	actor.resource(&"qi").current = 500.0
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(WEAPON), false, "reactivated once it can pay again")


## The reserve is what stops upkeep chipping an actor to zero and suspending on the
## very tick it empties the pool.
func test_upkeep_reserve_is_respected() -> void:
	var actor := _qi_actor(12.0)
	var upkeep := EquipmentUpkeep.new()
	# Needs 10 but holds only 12, so it could pay exactly - leaving 2, under the
	# reserve of 5. The reserve must refuse.
	var requirement := ItemRequirement.new()
	requirement.upkeep = {&"qi": 10.0}
	requirement.upkeep_reserve = {&"qi": 5.0}
	var def := _def_with(requirement)
	ItemsApi.attach(actor, 50)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	ItemsApi.equip_item(actor, WEAPON, def)
	var equipment := ItemsApi.equipment(actor)
	equipment.set_upkeep(upkeep)
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(WEAPON), true, "the reserve refuses the payment")
	assert_eq(actor.resource(&"qi").current, 12.0, "and the resource is untouched")


## A successful payment actually deducts, and only then.
func test_a_successful_payment_deducts_once() -> void:
	var actor := _qi_actor(100.0)
	var upkeep := EquipmentUpkeep.new()
	var def := _upkeep_item()
	ItemsApi.attach(actor, 50)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	ItemsApi.equip_item(actor, WEAPON, def)
	var equipment := ItemsApi.equipment(actor)
	equipment.set_upkeep(upkeep)
	upkeep.settle(actor, equipment)
	assert_eq(actor.resource(&"qi").current, 90.0, "one interval charged")
	upkeep.settle(actor, equipment)
	assert_eq(actor.resource(&"qi").current, 80.0, "two intervals charged")


## An item with no upkeep is never suspended, whatever else is equipped.
func test_items_without_upkeep_are_never_suspended() -> void:
	var actor := _qi_actor(0.0)
	ItemsApi.attach(actor, 50)
	var equipment := ItemsApi.equipment(actor)
	var upkeep := EquipmentUpkeep.new()
	equipment.set_upkeep(upkeep)
	var plain := _def_with(null)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(plain.id))
	ItemsApi.equip_item(actor, WEAPON, plain)
	upkeep.settle(actor, equipment)
	assert_eq(upkeep.suspended_slots().is_empty(), true, "nothing to suspend")


## Suspension is per slot, so one unaffordable item does not disable the rest.
func test_suspension_is_per_slot() -> void:
	var actor := _qi_actor(8.0)
	ItemsApi.attach(actor, 50)
	var equipment := ItemsApi.equipment(actor)
	var upkeep := EquipmentUpkeep.new()
	equipment.set_upkeep(upkeep)

	var costly := _upkeep_item()
	costly.id = &"costly"
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(costly.id))
	ItemsApi.equip_item(actor, Equipment.WEAPON, costly)
	for slot in [Equipment.WEAPON, Equipment.ARMOR]:
		var def := _upkeep_item() if slot == Equipment.WEAPON else _def_with(null)
		def.id = &"probe_%s" % String(slot)
		ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
		ItemsApi.equip_item(actor, slot, def)

	upkeep.settle(actor, equipment)
	assert_eq(upkeep.is_suspended(Equipment.WEAPON), true, "the costly one suspends")
	assert_eq(upkeep.is_suspended(Equipment.ARMOR), false, "the free one does not")
	assert_eq(equipment.equipped(Equipment.ARMOR) != null, true, "and stays equipped")
