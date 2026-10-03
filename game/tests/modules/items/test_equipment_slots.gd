extends TestCase

## Which slots an item may occupy is a gameplay rule, so it lives in `items/`
## next to the slots themselves and `ui/` reads it rather than keeping a copy.
##
## The rule is deliberately narrow. It confines the subtypes [ItemSubtype]
## declares — `weapon`, `armor`, `accessory`, `artifact` — and leaves every
## other subtype wearable anywhere, because content authors subtypes beyond those
## four and refusing them would be inventing a restriction nobody authored.
##
## `equip` used to return a bare `false` from five different branches. These tests
## name each one, because "it returned false" cannot tell a wrong slot from a
## full bag from unmet requirements, and cannot be asserted against at all.

const UNDECLARED_SUBTYPE := &"lens"


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	return actor


## An equipment def of the given subtype, with no roll_spec so the value is the
## authored one and a stat delta means what it says.
func _def(subcategory: StringName, attack: float = 0.0) -> ItemDef:
	var def := ItemDef.new()
	def.id = StringName("probe_%s" % subcategory)
	def.display_name = "Probe"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = subcategory
	def.stackable = false
	def.rarity = &"rare"
	def.realm = &"qi_refining"
	if attack > 0.0:
		def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": attack}]
	return def


## The gate is SATISFIABLE: from a legal prior state — the item in the bag, the
## slot empty — the correct slot accepts it and the stat actually moves.
func test_the_authored_slot_accepts_the_item_and_the_stat_moves() -> void:
	var actor := _hero()
	var weapon := _def(ItemSubtype.WEAPON, 25.0)
	ItemsApi.inventory(actor).add(weapon, 1)
	var before := actor.stats.derived(Stat.ATTACK_PHYSICAL)

	assert_eq(
		ItemsApi.equip_item(actor, Equipment.WEAPON, weapon),
		true,
		"a weapon equips into the weapon slot"
	)
	assert_eq(
		ItemsApi.equipment(actor).last_refusal(),
		"",
		"a successful equip leaves no refusal recorded"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL), before + 25.0, "the authored bonus is applied"
	)
	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.WEAPON).def_id, weapon.id, "the slot holds it"
	)


## The gate is NON-TRIVIAL: checked independently of the case above. A bare actor
## does not already pass — the slot is empty and contributes nothing before the
## equip, and a refusal leaves it that way rather than half-applying.
func test_the_gate_is_not_satisfied_before_the_equip_and_a_refusal_leaves_it_unsatisfied() -> void:
	var actor := _hero()
	var weapon := _def(ItemSubtype.WEAPON, 25.0)
	var before := actor.stats.derived(Stat.ATTACK_PHYSICAL)

	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.WEAPON), null, "a bare actor wears nothing"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL), before, "and gains nothing from the empty slot"
	)

	ItemsApi.inventory(actor).add(weapon, 1)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, weapon), false, "the wrong slot refuses")
	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.WEAPON),
		null,
		"so the weapon slot is still empty"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL), before, "and the bonus was never applied"
	)
	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.ARMOR), null, "nor did the wrong slot take it"
	)


## The refusal is nameable, not just false. This is the branch the rule exists
## for: a sword in the armour slot, which would charge the wrong upkeep.
func test_a_weapon_in_the_armor_slot_is_refused_and_names_the_branch() -> void:
	var actor := _hero()
	var weapon := _def(ItemSubtype.WEAPON, 25.0)
	ItemsApi.inventory(actor).add(weapon, 1)

	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, weapon), false, "refused")
	assert_eq(
		ItemsApi.equipment(actor).last_refusal(),
		Equipment.REASON_WRONG_SLOT,
		"the refusal names the subtype/slot mismatch, not some other branch"
	)
	assert_eq(
		ItemsApi.inventory(actor).find_instance(weapon.id) != null,
		true,
		"a refused item is still held, never silently consumed"
	)


## Every declared subtype is confined to its authored slots, and to nothing else.
## Asserted over the whole table so adding a slot cannot quietly widen a subtype.
func test_every_declared_subtype_is_confined_to_its_authored_slots() -> void:
	var expected := {
		ItemSubtype.WEAPON: [Equipment.WEAPON],
		ItemSubtype.ARMOR: [Equipment.ARMOR],
		ItemSubtype.ACCESSORY: [Equipment.ACCESSORY_A, Equipment.ACCESSORY_B],
		ItemSubtype.ARTIFACT: [Equipment.ARTIFACT],
	}
	for subtype in expected:
		var def := _def(StringName(subtype))
		var allowed: Array = expected[subtype]
		assert_eq(
			Equipment.SLOTS_BY_SUBTYPE.has(subtype),
			true,
			"subtype '%s' is declared and therefore constrained" % subtype
		)
		for slot in Equipment.SLOTS:
			var wants: bool = allowed.has(slot)
			assert_eq(
				Equipment.new().slots_for(def).has(slot),
				wants,
				"'%s' in slot '%s' is %s" % [subtype, slot, "allowed" if wants else "refused"]
			)


## An item whose subtype is outside the declared vocabulary gets NO ruling, and
## is still equippable anywhere wearable. Content authors subtypes beyond the
## four, and this rule must not make 483 authored items unequippable by accident.
func test_a_subtype_outside_the_declared_vocabulary_is_equippable_anywhere() -> void:
	var actor := _hero()
	var lens := _def(UNDECLARED_SUBTYPE, 5.0)
	ItemsApi.inventory(actor).add(lens, 1)

	assert_eq(
		Equipment.new().slots_for(lens).is_empty(),
		true,
		"an undeclared subtype gets no ruling, which is not the same as ruling every slot out"
	)
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.ARTIFACT, lens),
		true,
		"so it equips into any wearable slot like any other item"
	)
	assert_eq(ItemsApi.equipment(actor).equipped(Equipment.ARTIFACT).def_id, lens.id, "and is worn")
	# A second item, because equipping moves the first out of the bag: this is
	# about which slots the rule permits, not about how many copies exist.
	var lens_two := _def(UNDECLARED_SUBTYPE)
	lens_two.id = &"probe_lens_two"
	ItemsApi.inventory(actor).add(lens_two, 1)
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.WEAPON, lens_two), true, "including a different slot"
	)


## Every refusal branch names itself. Before this, all five returned a bare
## `false` and were indistinguishable, so none of them could be asserted.
func test_each_equip_refusal_names_its_own_branch() -> void:
	var actor := _hero()
	var weapon := _def(ItemSubtype.WEAPON)
	var equipment := ItemsApi.equipment(actor)
	ItemsApi.inventory(actor).add(weapon, 1)

	assert_eq(ItemsApi.equip_item(actor, &"tail", weapon), false, "an unknown slot is refused")
	assert_eq(equipment.last_refusal(), Equipment.REASON_NO_SUCH_SLOT, "and names the unknown slot")

	var herb := ItemDef.new()
	herb.id = &"probe_herb"
	herb.category = ItemCategory.MATERIAL
	# Non-stackable, so it is carried as an instance and actually reaches
	# `Equipment.equip`. A stack is refused earlier, by a different branch.
	herb.stackable = false
	ItemsApi.inventory(actor).add(herb, 1)
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.WEAPON, herb), false, "a non-equipment def is refused"
	)
	assert_eq(equipment.last_refusal(), Equipment.REASON_NOT_EQUIPMENT, "and names the category")

	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, weapon), false, "a wrong slot is refused")
	assert_eq(equipment.last_refusal(), Equipment.REASON_WRONG_SLOT, "and names the slot mismatch")

	# An instance belonging to a different definition than the one being equipped.
	# The id has to differ, or the two defs are the same def and nothing mismatches.
	var other := _def(ItemSubtype.WEAPON)
	other.id = &"probe_other_weapon"
	var mismatched := ItemsApi.generate(actor, other, 4242)
	assert_eq(
		ItemsApi.equipment(actor).equip(actor, Equipment.WEAPON, weapon, mismatched),
		false,
		"an instance that belongs to another def is refused"
	)
	assert_eq(
		equipment.last_refusal(),
		Equipment.REASON_INSTANCE_MISMATCH,
		"and names the mismatch rather than the slot"
	)
