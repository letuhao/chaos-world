extends TestCase

## WHY A MIRROR NEEDS SOMETHING THAT COMPARES IT TO THE ORIGINAL.
##
## `ItemActionRules` exists to answer "may this be used?" BEFORE the press, so the
## button is not offered for an action the facade will refuse. Its own docstring says
## the facade stays authoritative and these rules "mirror the facade's preconditions
## for feedback".
##
## A mirror that nothing compares to the original is a second copy of a fact, and a
## second copy drifts. It HAD drifted: `USABLE_ACTIVATIONS` listed `&"property"`, so a
## KEY item's Use button stayed lit while `ItemUse` refuses every PROPERTY activation
## — and nothing noticed, because nothing tested this file at all (BL-0601).
##
## ## Why these cases are written out one per category rather than derived
##
## The obvious generalisation is a loop over `ItemActivation.BY_CATEGORY` asking the
## panel and the facade the same question. That does not work, and it is worth saying
## why rather than leaving the next person to try it. There is no read-only facade
## function that answers "does this channel have a consumer": `spend_gate` is the
## SPEND half and allows an EQUIPMENT item, because an equipment item has nothing to
## spend — but `apply` refuses it as `not_usable`, because there is no arm for it.
## Comparing the panel to `spend_gate` therefore reports a disagreement on exactly the
## items the panel is RIGHT to block. Comparing to `apply` needs an actor and conflates
## "wrong channel" with "nothing to do".
##
## So each case states its category and what the facade does with it. A loop that
## restated the dispatch would pass against a dispatcher that had changed, which is
## the failure this file exists to catch.

# --- Fixtures ------------------------------------------------------------------


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {})
	ItemsApi.attach(actor)
	return actor


## One def of `category`. The activation is DERIVED from the category by
## `ItemActivation.for_category`, never stated here, so a fixture cannot disagree
## with the map it is meant to exercise.
func _def_of(category: StringName, def_id: StringName) -> ItemDef:
	var def := ItemDef.new()
	def.id = def_id
	def.display_name = "Mirror probe"
	def.category = category
	def.subcategory = &""
	def.grade = &"mortal"
	def.rarity = &"common"
	def.realm = &""
	def.stackable = category != ItemCategory.EQUIPMENT
	return def


func _carried(actor: Actor, def: ItemDef) -> Dictionary:
	assert_eq(
		ItemsApi.inventory(actor).add(def, 1),
		0,
		"'%s' enters the bag, so the panel is asked about a CARRIED item" % String(def.id),
	)
	return {"def": def, "def_id": def.id}


# --- The regressions -----------------------------------------------------------


## BL-0601 proper. A KEY resolves to the PROPERTY channel, and `ItemUse` refuses every
## PROPERTY activation before any effect resolves — so the control could only ever come
## back refused. It was lit anyway.
func test_a_key_items_use_button_is_blocked_and_the_facade_refuses_it() -> void:
	var actor := _hero()
	var def := _def_of(ItemCategory.KEY, &"probe_a_key")
	var row := _carried(actor, def)

	assert_ne(
		ItemActionRules.use_block_reason(actor, row),
		"",
		(
			"the Use button is offered for a KEY item, but the facade refuses every PROPERTY "
			+ "activation — the player is promised an action and then told no"
		),
	)
	assert_eq(
		StringName(def.activation()),
		ItemActivation.PROPERTY,
		(
			"a KEY no longer resolves to the PROPERTY channel, so this case is testing a "
			+ "category the facade now services differently and the panel needs re-reading"
		),
	)


## The other direction, and the reason this file exists rather than a one-line constant
## check: a panel that over-blocks is as wrong as one that over-promises. An EQUIPMENT
## item has no Use verb at all, and neither does a MATERIAL — `apply` reaches its
## default arm and refuses `not_usable`. The panel must say so BEFORE the press.
func test_equipment_and_materials_offer_no_use_button() -> void:
	var actor := _hero()
	for category in [ItemCategory.EQUIPMENT, ItemCategory.MATERIAL]:
		var def := _def_of(StringName(category), StringName("probe_%s" % String(category)))
		var row := _carried(actor, def)
		assert_ne(
			ItemActionRules.use_block_reason(actor, row),
			"",
			"the Use button is offered for a %s item, which has no use verb" % String(category),
		)


## And the two channels that DO have a consumer must not be caught by the rules above.
## A gate that refuses everything passes every "is it blocked" case in this file, so
## the green half has to be asserted too.
func test_consumables_and_manuals_still_offer_the_use_button() -> void:
	var actor := _hero()
	for pair in [
		[ItemCategory.CONSUMABLE, &"probe_a_pill"],
		[ItemCategory.TECHNIQUE, &"probe_a_manual"],
	]:
		var def := _def_of(StringName(pair[0]), StringName(pair[1]))
		var row := _carried(actor, def)
		assert_eq(
			ItemActionRules.use_block_reason(actor, row),
			"",
			(
				(
					"the Use button is dark for a CARRIED %s, which the facade does service; a "
					+ "gate that refuses everything would pass every other case in this file"
				)
				% String(pair[0])
			),
		)


## The shipped list is exactly the channels `apply` acts on, spelled out so a reader
## can check it against the dispatcher in one glance rather than by running anything.
## The claim-to-equip chain, which is criterion 3's equip half and which NOTHING in the repo
## proves. Every equip proof so far is a proof about the STARTER KIT: `test_item_pipeline`
## equips `armor_iron_helm`, which is in the bag before the fight, so "receive a boss drop ->
## equip it" has never actually been asserted for an item that arrived by claim.
##
## What this pins is the CHAIN, because each link was a separate suspect while BL-0725 was
## open and every link turned out to be sound:
##   - a claimed equipment drop lands as an INSTANCE, not a stack. ADR 0007 splits the two
##     representations, and `Inventory.find_instance` scans only `_instances`, so a stack
##     would be invisible to the equip gate even while the bag row listed it.
##   - the row the panel builds carries the instance's own `def_id`, which is what
##     `equip_shape_reason` matches on.
##   - `equip_block_reason` returns empty for such a row, so the control is OFFERED - the
##     refusal vocabulary is the gate, and an empty reason is the whole difference between a
##     live Equip and a grey one.
##   - the facade equips it and the item's authored modifier reaches the effective stat.
func test_a_claimed_drop_is_offered_equipped_and_raises_a_stat() -> void:
	var actor := _hero()
	var def := _def_of(ItemCategory.EQUIPMENT, &"probe_claimed_drop")
	# A wearable subtype and one authored fixed modifier, so the slot routing and the stat
	# delta are both real rather than incidental.
	def.subcategory = &"armor"
	var mods: Array[Dictionary] = [{"option_id": &"core_defense_physical", "value": 7.0}]
	def.fixed_modifiers = mods
	# The acquisition a claim performs: mint a realized instance and land it in the bag.
	# `ItemsApi.generate` routes a non-stackable def through `inv.add_instance`, which is the
	# same call `LootRewards` makes when it pays out (loot_rewards.gd:172).
	var instance := ItemsApi.generate(actor, def, 20261005)
	assert_ne(instance, null, "the drop mints a realized instance rather than a stack")
	assert_eq(
		ItemsApi.inventory(actor).find_instance(def.id) != null,
		true,
		(
			"and lands where the equip gate can see it: `find_instance` scans only _instances, so "
			+ "a drop that arrived as a stack would be listed in the bag and refused as not "
			+ "carried at the same time"
		),
	)
	var row := {"def": def, "def_id": def.id}
	assert_eq(
		String(ItemActionRules.equip_block_reason(actor, row)),
		"",
		(
			"Equip is OFFERED for a claimed equipment drop - the block reason IS the gate, and an "
			+ "empty reason is the entire difference between a live Equip and a grey one"
		),
	)
	var before := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_eq(ItemsApi.equip_item(actor, &"armor", def), true, "and the facade equips it")
	assert_ne(ItemsApi.equipment(actor).equipped(&"armor"), null, "the armor slot holds the drop")
	assert_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL) > before,
		true,
		"and the drop's own authored defense reaches the actor's effective stat",
	)


func test_the_usable_list_is_the_two_consuming_channels() -> void:
	assert_eq(
		ItemActionRules.USABLE_ACTIVATIONS,
		[ItemActivation.CONSUMED, ItemActivation.LEARNED] as Array[StringName],
		(
			"USABLE_ACTIVATIONS drifted from ItemUse's dispatcher. `apply` acts on "
			+ "CONSUMED and LEARNED, REFUSES PROPERTY via _refuse_read_only, and reaches "
			+ "not_usable for EQUIPPED and CRAFTED. Anything else in this list offers a "
			+ "control that cannot succeed."
		),
	)
