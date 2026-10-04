extends TestCase

## BL-0110, the ALLOWANCE half: the gate refuses a required progression input, and
## nothing else changed.
##
## `test_progression_roles.gd` proves the refusal and that the table is true. This
## file proves the other side, which is the half a refusal test cannot see: that
## the gate is a GATE and not a wall. A verb that refuses everything is
## indistinguishable, from the outside, from a working one -- the player can no
## longer heal, and every pill they hold is stranded rather than spent.
##
## Split out of `test_progression_roles.gd` so each file answers one question:
## that one asks WHAT IS RULED, this one asks WHAT IS STILL SPENDABLE.

## One authored pill a seed names, so the ruled side of the pair below is real
## shipped content rather than a fixture. Named here, never read from the table
## under test: a test that chose its subject from the table would pass whatever
## the table said.
const RULED_PILL := "mind_core_formation_breakthrough_pill"
## An authored pill no seed names. Its role is empty and its subtype is the same
## one the progression pills use, which is what makes it the control for the gate.
const UNRULED_PILL := "H1_mortal_breakthrough_pill"
## An authored, unruled consumable whose FIXED modifiers carry a restoration, so
## whether it restores is decided by content and not by a random roll. Gathered,
## which is the real acquisition route, and `food`, so it is nothing like a pill.
const EXPENDABLE := "F46_mortal_grainery_attack_speed_evasion_fortune"
## An authored, unruled consumable whose only fixed option is one its own category
## refuses, so the definition resolves to no effects at all.
const BASE_ONLY_TINCTURE := "A15_heaven_barmbrack_base"


func setup() -> void:
	ProgressionRoles.reset()


## An actor with the core pools a restoration needs, and an empty bag.
func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	return actor


## The item definition a seed-named id resolves to, read off the item content root
## rather than through `Crafting.resolve`, whose id-prefix fast path sends every
## `mind_*` id to `material/` first and then walks the whole tree.
func _def(item_id: String) -> ItemDef:
	return load("res://data/items/consumable/%s.tres" % item_id) as ItemDef


func test_a_genuinely_expendable_consumable_is_still_spent() -> void:
	# Without this half the fix is indistinguishable from disabling the verb, and a
	# test that only proves refusals proves nothing about whether the game works.
	var def := _def(EXPENDABLE)
	assert_ne(def, null, "%s resolves" % EXPENDABLE)
	if def == null:
		return
	assert_eq(ProgressionRoles.role_of(def.id), &"", "%s is authored as expendable" % EXPENDABLE)
	var actor := _hero()
	var pool := actor.resource(&"health")
	pool.change(-30.0)
	var wounded := pool.current
	ItemsApi.inventory(actor).add(def, 3)
	var result := ItemsApi.use_item(actor, def.id)
	assert_eq(bool(result.get("ok", false)), true, "an expendable consumable is spent")
	assert_eq(ItemsApi.inventory(actor).count(def.id), 2, "exactly one unit was consumed")
	assert_eq(pool.current > wounded, true, "and a pool actually rose")


func test_every_ruled_input_is_still_spendable_by_the_path_that_serves_it() -> void:
	# The half that would be a WORSE bug than the one fixed. `use_item` refuses a
	# progression input, and the gate is one edit away from becoming the rule every
	# verb consults: `consume_item` is the verb all three cultivation paths actually
	# call, so gating THAT would leave the player holding a pill no breakthrough can
	# ever be paid for -- unrecoverable, and far worse than a heal of 6.
	#
	# Swept across EVERY ruled id rather than one named pill, because the table is
	# content: a role that gates its own consumer strands exactly one realm, and a
	# single named pill would never notice which.
	var ids := ProgressionRoles.ruled_ids()
	assert_eq(ids.is_empty(), false, "the rule rules something at all")
	var actor := _hero()
	# A bag sized from the snapshot taken ABOVE, so a saturation cannot confound
	# the two verdicts: when the allowance is broken the units are never removed,
	# and a default bag would fill at 24 and make every later `use_item` answer
	# `not_carried` -- which reads as "not refused by the gate" and hides which
	# half actually broke. Snapshotted before the sweep, never read from it.
	actor.set_component(ItemsApi.INVENTORY_COMPONENT, Inventory.new(ids.size() + 8))
	var unresolved := 0
	var spendable := 0
	var stranded := 0
	# A `for` over the ruled ids, not a `while`: the collection is fixed by the
	# table and nothing in the body can add to it.
	for def_id in ids:
		var def := _def(String(def_id))
		if def == null:
			unresolved += 1
			continue
		# Carried FIRST, so the refusal read below is the GATE's answer and not
		# `not_carried`: an item the actor does not hold is refused before the gate
		# is reached, which would make the assertion true for the wrong reason.
		ItemsApi.inventory(actor).add(def, 1)
		var refused := ItemsApi.use_item(actor, def_id)
		if String(refused.get("reason", "")) != String(ItemUse.REASON_PROGRESSION_INPUT):
			spendable += 1
		# THE ALLOWANCE: the verb the three cultivation paths call is untouched, so
		# the gate is a gate and not a wall. Consumed here rather than left in the
		# bag, so the sweep holds one unit at a time rather than 300.
		if not ItemsApi.consume_item(actor, def_id):
			stranded += 1
	assert_eq(unresolved, 0, "every ruled id resolves to an authored definition")
	assert_eq(
		spendable,
		0,
		(
			"no ruled progression input is spendable from the inventory (%d of %d were)"
			% [spendable, ids.size()]
		)
	)
	assert_eq(
		stranded,
		0,
		(
			"and every one is still spendable by the path that serves it (%d of %d were not)"
			% [stranded, ids.size()]
		)
	)


func test_the_gate_leaves_an_unruled_pill_alone() -> void:
	# The distinction is the ROLE, not the shape. Two authored pills, one ruled and
	# one not: if the refusal keyed off the subtype, off the category, or off the
	# `restore_health` option every one of them carries, the unruled pill would be
	# gated too and a real heal would be lost. Read at the gate rather than through
	# `use_item`, because what this asserts is the DECISION -- what this item is
	# allowed to be spent on -- not the effect its random roll happened to produce.
	var ruled := _def(RULED_PILL)
	var unruled := _def(UNRULED_PILL)
	assert_ne(unruled, null, "%s resolves" % UNRULED_PILL)
	if unruled == null:
		return
	assert_eq(unruled.subcategory, ruled.subcategory, "both are the same authored subtype")
	assert_eq(unruled.category, ruled.category, "and the same authored category")
	assert_eq(ProgressionRoles.role_of(unruled.id), &"", "only the ruled one is ruled")
	assert_eq(
		String(ItemUse.spend_gate(unruled).get("reason", "")),
		"",
		"so the gate lets an ordinary pill through"
	)
	assert_eq(bool(ItemUse.preview(unruled, null)["spendable"]), true, "and preview agrees")
	assert_eq(
		String(ItemUse.spend_gate(ruled).get("reason", "")),
		String(ItemUse.REASON_PROGRESSION_INPUT),
		"while the ruled one is refused by the same question"
	)


func test_a_consumable_that_restores_nothing_is_refused_and_kept() -> void:
	# The third member of this family, and the one easiest to miss: a consumable
	# whose options resolve to nothing at all must not cost a unit. Reporting `ok`
	# there is BL-0110 one category over -- the verb decrements the stack and the
	# actor is identical afterwards.
	#
	# The subject is an authored tincture whose fixed `base_spirit` the catalog
	# declares for `equipment`/`technique`, so the `consumed` channel refuses the
	# option and the item resolves to no effects whatsoever. That is real shipped
	# content, not a fixture, and it is why the verb has nothing to charge for.
	#
	# Asked on a COPY with its roll spec dropped, because every authored consumable
	# rolls and a roll decides for itself whether this press lands. Copying rather
	# than mutating matters: the loaded resource is shared with every other suite in
	# the process, and clearing a spec on it would change what they roll too.
	var authored := _def(BASE_ONLY_TINCTURE)
	assert_ne(authored, null, "%s resolves" % BASE_ONLY_TINCTURE)
	if authored == null:
		return
	var fixed_only := authored.duplicate(true) as ItemDef
	fixed_only.roll_spec = {}
	fixed_only.id = &"fixed_only_tincture"
	assert_eq(ItemUse.spend_gate(fixed_only).is_empty(), true, "the gate allows it through")
	assert_eq(
		ItemEffects.resolve(fixed_only, null).size(),
		0,
		"its fixed option is refused by its own category, so it carries nothing at all"
	)
	var actor := _hero()
	var pool := actor.resource(&"health")
	pool.change(-50.0)
	var wounded := pool.current
	ItemsApi.inventory(actor).add(fixed_only, 1)
	var result := ItemsApi.use_item(actor, fixed_only.id)
	assert_eq(bool(result.get("ok", false)), false, "so there is nothing to restore")
	assert_eq(
		String(result.get("reason", "")),
		String(ItemUse.REASON_NO_EFFECT),
		"so it is refused by name"
	)
	assert_eq(ItemsApi.inventory(actor).count(fixed_only.id), 1, "and the unit was kept")
	assert_almost_eq(pool.current, wounded, "and no pool moved")
