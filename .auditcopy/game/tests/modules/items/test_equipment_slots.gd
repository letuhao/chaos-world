extends TestCase

## Which slots an item may occupy is a gameplay rule, so it lives in `items/`
## next to the slots themselves and `ui/` reads it rather than keeping a copy.
##
## The rule is AUTHORED CONTENT (`res://data/items/equipment_slots.json`), not a
## `const` naming whichever subtypes somebody remembered. It used to name four,
## which left the 488 authored equipment items typed `lens`, `greaves`,
## `bandolier`, `orb` or `gem` with no ruling at all — so a pair of greaves fit
## the weapon slot and a socket gem could be worn outright, paying its stats with
## no socket and no host. Content authors subtypes, so content decides where they
## go, and the guard that keeps it honest is
## `test_every_equipment_subtype_in_the_content_tree_is_ruled`.
##
## `equip` used to return a bare `false` from five different branches. These tests
## name each one, because "it returned false" cannot tell a wrong slot from a
## full bag from unmet requirements, and cannot be asserted against at all.

## The ruling this project makes, mirrored here so an edit to the authored table
## is a reviewed change rather than a silent widening. Keyed by subtype.
const AUTHORED_RULINGS := {
	ItemSubtype.WEAPON: [Equipment.WEAPON],
	ItemSubtype.ARMOR: [Equipment.ARMOR],
	ItemSubtype.ACCESSORY: [Equipment.ACCESSORY_A, Equipment.ACCESSORY_B],
	ItemSubtype.ARTIFACT: [Equipment.ARTIFACT],
	ItemSubtype.GREAVES: [Equipment.ARMOR],
	ItemSubtype.BANDOLIER: [Equipment.ARMOR],
	ItemSubtype.LENS: [Equipment.ACCESSORY_A, Equipment.ACCESSORY_B],
	ItemSubtype.ORB: [Equipment.ACCESSORY_A, Equipment.ACCESSORY_B],
}

## A subtype no authored content names. The permissive fallback has to survive for
## it, or adding a subtype would silently make the item unequippable everywhere.
const UNNAMED_SUBTYPE := &"probe_unnamed"
## The authored subtype that names no wearable slot at all.
const UNWEARABLE_SUBTYPE := ItemSubtype.GEM

const CONTENT_ROOT := "res://data"


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


## Every ruling the authored table makes is the one this project intends, and
## every ruling confines its subtype to exactly those slots. Asserted over the
## whole table, so adding a slot cannot quietly widen a subtype.
func test_every_authored_ruling_is_the_one_this_project_makes_and_confines_its_subtype() -> void:
	for subtype in AUTHORED_RULINGS:
		var def := _def(StringName(subtype))
		var allowed: Array = AUTHORED_RULINGS[subtype]
		assert_eq(
			ItemSlots.for_subtype(StringName(subtype)).size(),
			allowed.size(),
			"subtype '%s' is ruled on exactly the authored slots" % subtype
		)
		for slot in Equipment.SLOTS:
			var wants: bool = allowed.has(slot)
			assert_eq(
				Equipment.new().slots_for(def).has(slot),
				wants,
				"'%s' in slot '%s' is %s" % [subtype, slot, "allowed" if wants else "refused"]
			)
	assert_eq(
		(AUTHORED_RULINGS.keys() as Array).size(),
		ItemSubtype.EQUIPMENT_SUBTYPES.size() - 1,
		"every wearable equipment subtype the vocabulary declares is ruled here"
	)


## The soundness guard this file exists for: nothing shipped may rely on the
## permissive fallback. Every equipment subtype the authored content actually
## uses is ruled one way or the other, so a new subtype cannot land unruled and
## quietly fit every wearable slot. Before the ruling became content, 488 items
## were in exactly that state.
func test_every_equipment_subtype_in_the_content_tree_is_ruled() -> void:
	var found := _content_subtypes()
	assert_eq(found.is_empty(), false, "the content tree has equipment to check")
	for subtype in found:
		assert_eq(
			ItemSlots.is_ruled(subtype),
			true,
			(
				(
					"shipped equipment uses subtype '%s', which the authored slot rule does not "
					+ "rule — add a row to %s"
				)
				% [subtype, ItemSlots.TABLE_PATH]
			)
		)
	# And the flip side: the vocabulary is not padded with subtypes no content uses
	# and no rule names, which is how the gap opened in the first place.
	for subtype in ItemSubtype.EQUIPMENT_SUBTYPES:
		assert_eq(
			ItemSlots.is_ruled(subtype),
			true,
			"declared equipment subtype '%s' has a ruling" % subtype
		)


## Every equipment subtype the shipped `.tres` files under `res://data` declare.
## Read as text rather than loaded: the walk covers every definition in the game
## and `load()`ing eight thousand resources to count nine distinct strings is a
## cost this guard should not pay.
func _content_subtypes() -> Array[StringName]:
	var found: Array[StringName] = []
	for path in ContentScan.files_under(CONTENT_ROOT):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('script_class="ItemDef"'):
			continue
		if not text.contains('category = &"equipment"'):
			continue
		var sub := _property(text, "subcategory")
		if sub == "" or found.has(StringName(sub)):
			continue
		found.append(StringName(sub))
	return found


func _property(text: String, field: String) -> String:
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.begins_with(field + " = "):
			continue
		var value := trimmed.substr(field.length() + 3).strip_edges()
		if value.begins_with("&"):
			value = value.substr(1)
		return value.trim_prefix('"').trim_suffix('"')
	return ""


## A subtype the authored rule does not name gets NO ruling, and is still
## equippable anywhere wearable. Deliberately permissive, so a newly authored
## subtype is never unequippable by accident — and the guard above is what stops
## anything shipped from depending on it.
func test_a_subtype_the_authored_rule_does_not_name_is_still_equippable_anywhere() -> void:
	var actor := _hero()
	var unnamed := _def(UNNAMED_SUBTYPE, 5.0)
	ItemsApi.inventory(actor).add(unnamed, 1)

	assert_eq(
		Equipment.new().slots_for(unnamed).is_empty(),
		true,
		"an unnamed subtype gets no ruling, which is not the same as ruling every slot out"
	)
	assert_eq(ItemsApi.equipment(actor).is_wearable(unnamed), true, "so it is wearable")
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.ARTIFACT, unnamed),
		true,
		"so it equips into any wearable slot like any other item"
	)
	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.ARTIFACT).def_id, unnamed.id, "and is worn"
	)
	# A second item, because equipping moves the first out of the bag: this is
	# about which slots the rule permits, not about how many copies exist.
	var unnamed_two := _def(UNNAMED_SUBTYPE)
	unnamed_two.id = &"probe_unnamed_two"
	ItemsApi.inventory(actor).add(unnamed_two, 1)
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.WEAPON, unnamed_two),
		true,
		"including a different slot"
	)


## The gate is NON-TRIVIAL for an unwearable subtype in every slot, and it names
## its own branch. A socket gem is the concrete case: its fixed options are on the
## equipped channel, so wearing one directly applied its stats with no socket, no
## host and no reagent — the whole socket program bypassed for free.
func test_a_subtype_authored_as_unwearable_is_refused_in_every_slot_and_says_so() -> void:
	var actor := _hero()
	var gem := _def(UNWEARABLE_SUBTYPE, 30.0)
	ItemsApi.inventory(actor).add(gem, 1)

	assert_eq(ItemsApi.equipment(actor).is_wearable(gem), false, "a gem is not wearable")
	for slot in Equipment.SLOTS:
		assert_eq(
			ItemsApi.equip_item(actor, slot, gem),
			false,
			"a gem is refused in slot '%s' — it belongs in a socket, not on a body" % slot
		)
		assert_eq(
			ItemsApi.equipment(actor).last_refusal(),
			Equipment.REASON_UNWEARABLE,
			"slot '%s' names the unwearable branch, not a wrong slot" % slot
		)
		assert_eq(ItemsApi.equipment(actor).equipped(slot), null, "slot '%s' took nothing" % slot)
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL),
		_hero().stats.derived(Stat.ATTACK_PHYSICAL),
		"and no slot ever applied its stats"
	)
	assert_eq(
		ItemsApi.inventory(actor).find_instance(gem.id) != null,
		true,
		"a refused item is still held, never silently consumed"
	)


## The two halves of "no opinion" are told apart by a named predicate rather than
## by the shape of the answer. Both answer `[]` from `slots_for`; only one of them
## is wearable, and a caller that cannot tell them apart offers the player a
## choice that can never succeed.
func test_no_opinion_and_unwearable_are_distinguishable_before_the_equip_is_attempted() -> void:
	var equipment := Equipment.new()
	var unnamed := _def(UNNAMED_SUBTYPE)
	var gem := _def(UNWEARABLE_SUBTYPE)
	assert_eq(equipment.slots_for(unnamed).is_empty(), true, "an unnamed subtype rules nothing")
	assert_eq(equipment.slots_for(gem).is_empty(), true, "so does an unwearable one")
	assert_eq(equipment.is_wearable(unnamed), true, "but only the first can be worn")
	assert_eq(equipment.is_wearable(gem), false, "the second cannot")


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
