extends TestCase

## BL-0110: the inventory's Use verb may never spend a REQUIRED PROGRESSION
## INPUT, and may never spend a read-only item either.
##
## The defect it fixes: `ItemsApi.use_item` applied a generic one-shot effect to
## whatever it was handed and then removed the unit. On a breakthrough pill that
## healed 6 health — a pool the pill was never for — and deleted the only copy of
## the price of an attempt. A button that decrements a number is not acquisition.
##
## Four independent things are proved here, and each fails on its own:
##
##   1. CONTENT. Every item a realm seed names as a progression input carries a
##      role, and every role in the table is named by a seed. Both directions,
##      because either alone is blind: one lets a pill go unruled, the other lets
##      a role be invented for an item nothing consumes.
##   2. THE REFUSAL. A held progression pill is refused by name, keeps its unit,
##      and applies nothing to any pool.
##   3. THE ALLOWANCE. A genuinely expendable consumable still succeeds from the
##      same prior state, so the gate is a gate and not a wall.
##   4. NON-TRIVIALITY. A bare actor is refused before the gate is even reached, so
##      half 2 is not the only way to fail and the guard is not vacuous.
##
## The seed sweep reads `data/*/realms/*.tres` as TEXT: a bounded, one-way read of
## authored content in a test, not a runtime edge. It is what makes the table
## provable against the authority that writes it rather than a second copy of it.

## The three cultivation paths, and the seed field behind each role. The suffix is
## the field's own name with `_item` dropped, so a new realm field is a new row
## here rather than a new branch in the rule.
const SEED_ROOTS := {"body_cultivation": "body", "qi_cultivation": "qi", "mind_cultivation": "mind"}
const SEED_FIELDS := {
	"breakthrough_item": "breakthrough",
	"strengthening_item": "strengthening",
	"training_item": "training",
	"recovery_item": "recovery",
	"sea_catalyst": "sea_catalyst",
}
## One authored pill per path, so a single broken path cannot hide behind the
## other two. Named by role, never picked from the table: a test that chose its
## subject from the table under test would pass whatever the table said.
const PILL_BY_ROLE := {
	"body_breakthrough": "body_core_formation_breakthrough_pill",
	"qi_breakthrough": "qi_core_formation_breakthrough_pill",
	"mind_breakthrough": "mind_core_formation_breakthrough_pill",
}
## An authored, unruled consumable whose FIXED modifiers carry a restoration, so
## whether it restores is decided by content and not by a random roll. Gathered,
## which is the real acquisition route, and `food`, so it is nothing like a pill.
const EXPENDABLE := "F46_mortal_grainery_attack_speed_evasion_fortune"
## An authored pill no seed names. Its role is empty and its subtype is the same one
## the progression pills use, which is what makes it the control for the gate.
const UNRULED_PILL := "H1_mortal_breakthrough_pill"
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


## Every `(item_id, role)` the three realm-seed trees declare.
func _seeded_roles() -> Array:
	var out: Array = []
	for root_dir in SEED_ROOTS.keys():
		var short_path := String(SEED_ROOTS[root_dir])
		for path in ContentScan.files_under("res://data/%s/realms" % root_dir):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var fields := line.strip_edges().split(" = ", false)
				if fields.size() != 2 or not SEED_FIELDS.has(fields[0]):
					continue
				var item_id := fields[1].trim_prefix('&"').trim_suffix('"')
				if not item_id.is_empty():
					out.append([item_id, "%s_%s" % [short_path, SEED_FIELDS[fields[0]]]])
	return out


# --- 1. Content -------------------------------------------------------------


func test_every_progression_input_a_seed_names_is_ruled_and_resolves() -> void:
	var seeded := _seeded_roles()
	assert_eq(seeded.is_empty(), false, "the realm seeds name progression inputs at all")
	var unresolved := 0
	var unruled := 0
	var wrong_role := 0
	for row in seeded:
		var item_id := String(row[0])
		var role := String(row[1])
		var def := _def(item_id)
		if def == null:
			unresolved += 1
			continue
		var authored := ProgressionRoles.role_of(def.id)
		if authored == &"":
			unruled += 1
		elif String(authored) != role:
			wrong_role += 1
	assert_eq(unresolved, 0, "every seeded progression input resolves to an item definition")
	assert_eq(unruled, 0, "every seeded progression input is ruled, so Use can never destroy it")
	assert_eq(wrong_role, 0, "and every one carries the role its seed field implies")


func test_the_rule_names_no_item_no_seed_names() -> void:
	# The other direction. Without it a typo'd or retired row would gate an item
	# nothing consumes — a progression input the player is then forbidden to use
	# with no path to spend it, which is a worse dead end than the one fixed.
	var seeded := {}
	for row in _seeded_roles():
		seeded[String(row[0])] = true
	var invented := 0
	for def_id in ProgressionRoles.ruled_ids():
		if not seeded.has(String(def_id)):
			invented += 1
	assert_eq(invented, 0, "no role is authored for an item no realm seed names")


func test_the_rule_covers_every_cultivation_path_and_role() -> void:
	# A rule that only covers the body path passes both directions above while
	# leaving 200 pills destroyable, because their ids are simply not in the table.
	# So the rule is checked against the shape the seeds are authored in.
	var roles := {}
	for def_id in ProgressionRoles.ruled_ids():
		roles[String(ProgressionRoles.role_of(def_id))] = true
	for path_id in ["body", "qi", "mind"]:
		for role_suffix in ["breakthrough", "recovery"]:
			assert_eq(
				roles.has("%s_%s" % [path_id, role_suffix]),
				true,
				"%s_%s progression inputs are ruled" % [path_id, role_suffix]
			)


# --- 2. The refusal ---------------------------------------------------------


func test_a_progression_input_is_refused_by_name_and_survives_the_press() -> void:
	for role in PILL_BY_ROLE.keys():
		var item_id := String(PILL_BY_ROLE[role])
		var def := _def(item_id)
		assert_ne(def, null, "%s resolves" % item_id)
		if def == null:
			continue
		var actor := _hero()
		actor.resource(&"health").change(-40.0)
		var held := actor.resource(&"health").current
		ItemsApi.inventory(actor).add(def, 1)
		var result := ItemsApi.use_item(actor, StringName(item_id))
		assert_eq(bool(result.get("ok", false)), false, "%s is refused" % item_id)
		assert_eq(
			String(result.get("reason", "")), String(ItemUse.REASON_PROGRESSION_INPUT), "named"
		)
		assert_eq(
			String(result.get("role", "")), String(role), "and names the path it serves: %s" % role
		)
		assert_eq(ItemsApi.inventory(actor).count(StringName(item_id)), 1, "%s survived" % item_id)
		# The pill carries a `restore_health` option, so the defect was never that
		# the heal was missing. It is that pressing the button charged the player a
		# progression item for a heal it was never meant to give.
		assert_almost_eq(
			actor.resource(&"health").current, held, "and nothing was applied to any pool"
		)


func test_a_refused_spend_does_not_release_a_quick_use_binding() -> void:
	# The second verb that spends through `items`. It must not empty itself either:
	# a bar entry pointing at a progression pill has to keep firing the refusal
	# rather than silently resetting the slot the player bound.
	var actor := _hero()
	var def := _def(String(PILL_BY_ROLE["mind_breakthrough"]))
	ItemsApi.inventory(actor).add(def, 1)
	QuickUseApi.assign_slot(actor, 0, def.id)
	var result: Dictionary = QuickUseApi.use_slot(actor, 0)
	assert_eq(bool(result.get("ok", false)), false, "the bar's spend is refused too")
	assert_eq(
		String((QuickUseApi.summary(actor)["slots"][0] as Dictionary)["def_id"]),
		String(def.id),
		"and the binding survives a refused spend"
	)


func test_a_read_only_channel_is_refused_instead_of_destroyed() -> void:
	# The same defect, one category over: `key_reach` is READ by loot, `trade_value`
	# by economy, and neither spends the key. Pressing Use destroyed it and changed
	# nothing, which is BL-0110 with a worse trade.
	var actor := _hero()
	var key := ItemDef.new()
	key.id = &"seal_of_a_locked_hall"
	key.category = ItemCategory.KEY
	key.subcategory = &"writ"
	key.stackable = true
	key.rarity = &"common"
	key.realm = &"qi_refining"
	key.fixed_modifiers = [{"option_id": &"key_reach", "value": 4.0}]
	ItemsApi.inventory(actor).add(key, 1)
	var result := ItemsApi.use_item(actor, key.id)
	assert_eq(bool(result.get("ok", false)), false, "a key is not spendable")
	assert_eq(String(result.get("reason", "")), String(ItemUse.REASON_NO_SPEND_CONSUMER), "named")
	assert_eq(ItemsApi.inventory(actor).count(key.id), 1, "the key survived")
	assert_eq(
		float((result.get("properties", {}) as Dictionary).get("key_reach", 0.0)),
		4.0,
		"and the numbers still ride along for a caller that only wanted to read them"
	)
	var coin := ItemDef.new()
	coin.id = &"a_single_coin"
	coin.category = ItemCategory.CURRENCY
	coin.stackable = true
	coin.rarity = &"common"
	coin.fixed_modifiers = [{"option_id": &"trade_value", "value": 12.0}]
	ItemsApi.inventory(actor).add(coin, 5)
	assert_eq(
		bool(ItemsApi.use_item(actor, coin.id).get("ok", false)), false, "currency is not spendable"
	)
	assert_eq(ItemsApi.inventory(actor).count(coin.id), 5, "and five coins are still five coins")


func test_equipment_and_material_still_refuse_for_their_own_reason() -> void:
	# `not_usable` is its own branch with its own reason, and merging it into the
	# read-only refusal would hide "this item has no Use verb" behind "this item has
	# no consumer" — two different answers to two different player questions.
	for category in [ItemCategory.EQUIPMENT, ItemCategory.MATERIAL]:
		var def := ItemDef.new()
		def.id = StringName("no_verb_%s" % category)
		def.category = category
		def.stackable = true
		def.rarity = &"common"
		var actor := _hero()
		ItemsApi.inventory(actor).add(def, 1)
		var result := ItemsApi.use_item(actor, def.id)
		assert_eq(
			String(result.get("reason", "")),
			String(ItemUse.REASON_NOT_USABLE),
			"%s has no Use verb at all" % category
		)


# --- 3. The allowance -------------------------------------------------------


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


func test_the_gate_leaves_an_unruled_pill_alone() -> void:
	# The distinction is the ROLE, not the shape. Two authored pills, one ruled and
	# one not: if the refusal keyed off the subtype, off the category, or off the
	# `restore_health` option every one of them carries, the unruled pill would be
	# gated too and a real heal would be lost. Read at the gate rather than through
	# `use_item`, because what this asserts is the DECISION -- what this item is
	# allowed to be spent on -- not the effect its random roll happened to produce.
	var ruled := _def(String(PILL_BY_ROLE["mind_breakthrough"]))
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


# --- 4. Non-triviality ------------------------------------------------------


func test_a_bare_actor_is_refused_before_the_gate_is_reached() -> void:
	# The gate must not be the ONLY thing refusing, or "the gate fires" and "the
	# verb is simply broken" read the same from the outside.
	var actor := _hero()
	var result := ItemsApi.use_item(actor, StringName(PILL_BY_ROLE["mind_breakthrough"]))
	assert_eq(bool(result.get("ok", false)), false, "nothing carried, nothing spent")
	assert_eq(
		String(result.get("reason", "")), "not_carried", "refused before the spend gate is asked"
	)
	assert_eq(
		bool(ItemUse.spend_gate(null).get("ok", false)), false, "a null definition is refused too"
	)


func test_the_gate_is_asked_even_for_a_def_the_bag_never_knew() -> void:
	# `use_item` resolves a definition the inventory does not hold a reference to, so
	# the gate is a property of the DEFINITION, not of the carried `def_ref`, and
	# cannot be bypassed by handing the verb a definition the bag never saw.
	var def := _def(String(PILL_BY_ROLE["qi_breakthrough"]))
	var actor := _hero()
	# A fresh inventory whose def_ref came from the content tree, not from the add
	# that built the previous bag.
	actor.set_component(ItemsApi.INVENTORY_COMPONENT, Inventory.new(4))
	var gate := ItemUse.spend_gate(def)
	assert_eq(String(gate.get("reason", "")), String(ItemUse.REASON_PROGRESSION_INPUT), "refused")
	assert_eq(bool(ItemsApi.use_item(actor, def.id).get("ok", false)), false, "and refused again")


# --- Persistence ------------------------------------------------------------


func test_a_progression_input_survives_the_save_round_trip_it_was_refused_for() -> void:
	# The gate is authored content, not actor state, so a restored bag must be
	# refused by exactly the verb that refused it before. If the role were ever
	# carried in the payload instead, a save that dropped it would hand the player
	# a destroyable pill.
	var def := _def(String(PILL_BY_ROLE["body_breakthrough"]))
	var actor := _hero()
	ItemsApi.inventory(actor).add(def, 2)
	var payload := ItemsApi.serialize(actor)
	var restored := _hero()
	ItemsApi.deserialize(restored, payload)
	assert_eq(ItemsApi.inventory(restored).count(def.id), 2, "both units came back from the save")
	var result := ItemsApi.use_item(restored, def.id)
	assert_eq(
		String(result.get("reason", "")), String(ItemUse.REASON_PROGRESSION_INPUT), "still refused"
	)
	assert_eq(ItemsApi.inventory(restored).count(def.id), 2, "and both units still survived")
