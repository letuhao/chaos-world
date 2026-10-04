extends TestCase

## Criterion 7 (FAILURE REACHABLE) for the ITEM PROGRAM.
##
## `test_failure_branches_reachable.gd` is the repo's suite for this criterion, and it
## carries 120 assertions — while naming `ItemsApi` exactly twice, both in setup. No
## `equip_item`, no `use_item`, no `SocketApi`, no `LootApi`, no `Crafting`. So the
## criterion was met elsewhere and unmet here, which is the shape that hides: "the
## screen is reachable" and "its refusal branches are named" are different claims and
## only the first was tested.
##
## Every refusal below is named with the CONCRETE INPUT STATE that causes it, because a
## refusal nobody can name is a bug report rather than a contract. Each is reached
## through `ItemsApi` — the production verb the workbench screen's own action bar calls
## — not through an internal, so a player can cause every one of them.
##
## The reasons are the SHIPPED strings, asserted as written here rather than
## restated: `ItemUse` and `Equipment` already publish each one as a named constant,
## and a copy in this file would let the wording drift while the assertion passed
## anyway.

# --- The shipped reasons, named once ------------------------------------------
#
# Named so a test asserts what production emits. Sourced from the constants
# themselves: `ItemUse.REASON_*`, `Equipment.REASON_*`.

## `ItemsApi.use_item`, for an id the bag holds no copy of.
const R_NOT_CARRIED := "not_carried"
## `ItemUse.apply`, for a category with no Use verb — `ItemActivation.BY_CATEGORY`
## sends `equipment` to `equipped` and `material` to `crafted`, and NEITHER is one of
## the three channels `apply` matches, so both land on its refusal arm.
const R_NOT_USABLE := "not_usable"
## `ItemUse.spend_gate`, for an id a realm seed names as the price of an attempt.
const R_PROGRESSION_INPUT := "progression_input"
## `ItemUse._refuse_read_only`, for a PROPERTY-channel item carrying no positive
## property value. Distinct from `no_spend_consumer`: that one means the channel has
## no consumer THAT SPENDS it, this one means the item carries nothing to read.
const R_NO_EFFECT := "no_applicable_effect"
## `Equipment.equip`, for a def whose subtype names a different slot.
const R_WRONG_SLOT := "wrong_slot_for_subtype"
## `Equipment.equip`, for a def that is not equipment at all.
const R_NOT_EQUIPMENT := "not_equipment"

## An id the authored progression table really rules. Read from
## `res://data/items/progression_roles.json`, which is the table `ProgressionRoles`
## loads and cross-checks against the realm seeds in both directions — so this is
## authored content, not a probe that happens to collide with a rule.
const RULED_PILL := &"body_core_formation_breakthrough_pill"
const RULED_PILL_CATEGORY := ItemCategory.CONSUMABLE


func setup() -> void:
	ProgressionRoles.reset()


## Nothing here is a Node: every fixture is a RefCounted `Actor` and a stack of
## `ItemDef`s the inventory owns, so there is nothing to detach and free. Stated
## rather than left implicit, because an unexplained absence of teardown is
## indistinguishable from a leak until someone reads it.
func teardown() -> void:
	pass


# --- Fixtures ------------------------------------------------------------------


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {})
	ItemsApi.attach(actor)
	return actor


## A def of `category`/`subcategory` under `def_id`, with no roll_spec so anything the
## refusal reports is the authored value rather than a roll.
func _def(def_id: StringName, category: StringName, subcategory: StringName) -> ItemDef:
	var def := ItemDef.new()
	def.id = def_id
	def.display_name = "Probe"
	def.category = category
	def.subcategory = subcategory
	def.grade = &"mortal"
	def.rarity = &"common"
	def.realm = &""
	def.stackable = category != ItemCategory.EQUIPMENT
	return def


func _carry(actor: Actor, def: ItemDef) -> void:
	assert_eq(ItemsApi.inventory(actor).add(def, 1), 0, "'%s' enters the bag" % String(def.id))


## A refused spend must leave the bag alone, so each case below counts the stack
## before and after rather than trusting the reason string alone. A refusal that
## consumed the stack would be BL-0110's defect wearing a different name.
func _stack_count(actor: Actor, def_id: StringName) -> int:
	return ItemsApi.inventory(actor).count(def_id)


## INPUT STATE: the bag holds no copy of the id. This is the refusal a player meets
## first, because the workbench keeps a selection while the row underneath it can be
## consumed by something else — and it is the only one of these that leaves the caller
## unable to tell "never had it" from "already spent it".
func test_using_an_id_the_bag_does_not_hold_is_refused_not_carried() -> void:
	var actor := _hero()
	var outcome := ItemsApi.use_item(actor, &"probe_never_carried")
	assert_eq(String(outcome.get("reason", "")), R_NOT_CARRIED, "an absent id is refused by name")
	assert_eq(bool(outcome.get("ok", true)), false, "a refusal never reports ok (BL-0110)")


## INPUT STATE: an EQUIPMENT item in the bag, and the Use control pressed.
## `ItemActivation.for_category` maps `equipment` to `equipped`, which is not one of
## the three channels `ItemUse.apply` matches, so it lands on the refusal arm.
##
## The bag is left untouched: a refusal that consumed the stack would be the BL-0110
## defect wearing a different name, so this asserts the count as well as the reason.
func test_using_equipment_is_refused_because_equipment_has_no_use_verb() -> void:
	var actor := _hero()
	var helm := _def(&"probe_helm", ItemCategory.EQUIPMENT, ItemSubtype.ARMOR)
	_carry(actor, helm)
	var before := _stack_count(actor, helm.id)

	var outcome := ItemsApi.use_item(actor, helm.id)
	assert_eq(
		String(outcome.get("reason", "")),
		R_NOT_USABLE,
		"equipment resolves to the `equipped` channel, which has no Use verb"
	)
	assert_eq(_stack_count(actor, helm.id), before, "and the refused item is still in the bag")


## INPUT STATE: a MATERIAL in the bag. The second shape of the same refusal, and it
## is asserted separately because it fails for a different reason: `material` maps to
## `crafted`, which is a real channel with a real consumer (`ItemsApi.craft` spends
## it) and yet still is not a USE verb. One assertion covering both would pass on
## either mapping and catch neither.
func test_using_a_material_is_refused_because_crafting_spends_it_not_use() -> void:
	var actor := _hero()
	var ore := _def(&"probe_ore", ItemCategory.MATERIAL, ItemSubtype.ORE)
	_carry(actor, ore)
	var before := _stack_count(actor, ore.id)

	var outcome := ItemsApi.use_item(actor, ore.id)
	assert_eq(
		String(outcome.get("reason", "")),
		R_NOT_USABLE,
		"a material is CRAFTED, which is spent by crafting rather than used"
	)
	assert_eq(_stack_count(actor, ore.id), before, "and the refused material is still in the bag")


## INPUT STATE: a def whose id a realm seed names as the price of an attempt, sitting
## in the bag with the Use control pressed. This is BL-0110's own defect and the reason
## the refusal exists: the pill would otherwise apply a generic one-shot effect and
## delete the only copy of the price of a breakthrough.
##
## The assertion that matters most is the last one — the role is carried in the refusal
## so a screen can name WHICH path the item belongs to, and a refusal that said only
## "no" would leave the player with no way to act on it.
func test_using_a_required_progression_input_is_refused_and_says_which_path() -> void:
	var actor := _hero()
	var pill := _def(RULED_PILL, RULED_PILL_CATEGORY, &"pill")
	_carry(actor, pill)
	var before := _stack_count(actor, pill.id)

	var outcome := ItemsApi.use_item(actor, pill.id)
	assert_eq(
		String(outcome.get("reason", "")),
		R_PROGRESSION_INPUT,
		"a required progression input is never spendable from the inventory"
	)
	assert_eq(
		_stack_count(actor, pill.id),
		before,
		"the only copy of the price of an attempt survives the press"
	)
	assert_ne(
		String(outcome.get("role", "")),
		"",
		"the refusal names the path that owns the item, so a screen can say which"
	)


## INPUT STATE: a KEY in the bag carrying no positive property value. `key` maps to the
## PROPERTY channel, whose consumer is a READ — `key_reach` is read by loot, never
## spent — so `spend_gate` refuses before any effect is resolved. This case is the
## `no_applicable_effect` arm rather than `no_spend_consumer`: there is nothing to read
## AND nothing that spends, and collapsing the two would tell a player holding an empty
## key that the problem is a missing consumer.
func test_using_a_read_only_channel_with_nothing_to_read_is_refused() -> void:
	var actor := _hero()
	var token := _def(&"probe_key", ItemCategory.KEY, &"token")
	_carry(actor, token)
	var before := _stack_count(actor, token.id)

	var outcome := ItemsApi.use_item(actor, token.id)
	assert_eq(
		String(outcome.get("reason", "")),
		R_NO_EFFECT,
		"a read-only channel carrying nothing resolves to no effect at all"
	)
	assert_eq(
		_stack_count(actor, token.id),
		before,
		"and the key survives, because destroying it would change nothing"
	)


## INPUT STATE: armor in the bag, and the WEAPON slot chosen. The authored table
## (`res://data/items/equipment_slots.json`) rules `armor` to the armor slot alone, so
## this is a refusal the CONTENT decides rather than a rule the test restates.
func test_equipping_armor_into_the_weapon_slot_is_refused_by_the_authored_ruling() -> void:
	var actor := _hero()
	var plate := _def(&"probe_plate", ItemCategory.EQUIPMENT, ItemSubtype.ARMOR)
	_carry(actor, plate)

	assert_eq(
		ItemsApi.equip_item(actor, Equipment.WEAPON, plate),
		false,
		"armor does not fit the weapon slot"
	)
	assert_eq(
		ItemsApi.equipment(actor).last_refusal(),
		R_WRONG_SLOT,
		"and the refusal names the authored ruling rather than a bare false"
	)
	assert_eq(ItemsApi.equipment(actor).equipped(Equipment.ARMOR), null, "the armor slot is empty")


## INPUT STATE: a CONSUMABLE chosen for equip. The second shape of a structural
## refusal, asserted separately because it is decided before the slot ruling is
## consulted — a test that only checked "it did not equip" would pass on either.
func test_equipping_a_consumable_is_refused_before_any_slot_is_consulted() -> void:
	var actor := _hero()
	var draught := _def(&"probe_draught", ItemCategory.CONSUMABLE, &"draught")
	# NOT stackable, and that is load-bearing rather than incidental. `equip_item`
	# resolves the item with `find_instance` (api.gd:77), which finds only unstacked
	# rows; a stacked probe returns false at that line and never reaches the kind
	# check, so `last_refusal()` stays empty and this test would assert nothing.
	draught.stackable = false
	_carry(actor, draught)

	assert_eq(
		ItemsApi.equip_item(actor, Equipment.ARMOR, draught), false, "a consumable is not equipment"
	)
	assert_eq(
		ItemsApi.equipment(actor).last_refusal(),
		R_NOT_EQUIPMENT,
		"and it is refused as the wrong KIND before the slot ruling is reached"
	)
