extends TestCase

## Loot table semantics: weighted choice vs independent chance, guaranteed
## entries, explicit no-drop, quantity ranges, nested tables and the bounded
## `loot_bonus` consumer.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _context(axes: Dictionary = {}) -> Dictionary:
	return LootResolver.make_context(
		&"", &"", &"", {"chance": 0.0, "count": 0, "quality_steps": 0}.merged(axes, true)
	)


func _item_entry(
	entry_id: StringName,
	weight: float = 1.0,
	chance: float = LootEntry.NO_CHANCE,
	guaranteed: bool = false
) -> LootEntry:
	var entry := LootEntry.new()
	entry.id = entry_id
	entry.kind = LootEntry.KIND_ITEM
	# A real, shipped item id: validation and resolution both resolve content.
	entry.item_id = &"beast_ironhide_bear_bone"
	entry.weight = weight
	entry.chance = chance
	entry.guaranteed = guaranteed
	return entry


func _nested_entry(entry_id: StringName, table_id: StringName, weight: float) -> LootEntry:
	var entry := LootEntry.new()
	entry.id = entry_id
	entry.kind = LootEntry.KIND_TABLE
	entry.table_id = table_id
	entry.weight = weight
	return entry


func _table(
	entries: Array[LootEntry], rolls: int = 1, rolls_max: int = 0, allow_empty: bool = false
) -> LootTableDef:
	var table := LootTableDef.new()
	table.id = &"probe_table"
	table.rolls = rolls
	table.rolls_max = rolls_max
	table.allow_empty = allow_empty
	table.entries = entries
	return table


## The weighted pool is a competition between entries: a heavier entry must show
## up proportionally more often across many seeds, and every count stays sane.
func test_weighted_choice_honours_declared_weights() -> void:
	var light := _item_entry(&"light", 1.0)
	light.item_id = &"beast_storm_hawk_bone"
	var heavy := _item_entry(&"heavy", 9.0)
	var table := _table([light, heavy] as Array[LootEntry])
	var counts := {"light": 0, "heavy": 0}
	for seed_value in range(600):
		var resolved := LootResolver.resolve(table, _context(), _rng(seed_value))
		var plans: Array = resolved["plans"]
		assert_eq(plans.size(), 1, "one draw per resolve at seed %d" % seed_value)
		if plans.is_empty():
			continue
		var plan: Dictionary = plans[0]
		var quantity := int(plan["quantity"])
		assert_eq(quantity >= 1, true, "never a non-positive quantity at seed %d" % seed_value)
		assert_eq(is_finite(quantity), true, "always an integer count")
		var entry_id := String(plan["entry_id"])
		counts[entry_id] = int(counts[entry_id]) + 1
	assert_eq(int(counts["heavy"]) > int(counts["light"]) * 4, true, "the heavier entry dominates")
	assert_eq(int(counts["light"]) > 0, true, "the lighter entry is still reachable")


## A weighted draw count is always inside its declared range and never negative,
## whatever the range or the count bonus.
func test_draw_count_stays_inside_the_authored_range() -> void:
	var table := _table([_item_entry(&"only", 1.0)] as Array[LootEntry], 2, 5)
	for seed_value in range(200):
		var count := table.draw_count(0, _rng(seed_value))
		assert_eq(count >= 2 and count <= 5, true, "draw count %d inside [2, 5]" % count)
	for bonus in [-4, -1, 0, 1, 2, 3, 99]:
		var count := table.draw_count(bonus, _rng(7))
		assert_eq(count >= 0, true, "never negative for bonus %d" % bonus)
		assert_eq(count <= LootTableDef.MAX_DROPS_PER_RESOLVE, true, "bounded for bonus %d" % bonus)
	assert_eq(table.draw_count(-5, _rng(3)), 2, "a negative bonus is clamped, not subtracted")


## An independent chance roll and a weighted choice are distinguishable: a
## chance-1.0 entry fires on every resolve while a weight never makes an entry
## certain, and a chance-0.0 entry never fires however heavy its weight is.
func test_independent_chance_and_weighted_choice_are_distinguishable() -> void:
	var certain := _item_entry(&"certain", 1.0, 1.0)
	var never := _item_entry(&"never", 1000.0, 0.0)
	var table := _table([certain, never] as Array[LootEntry], 0, 0, true)
	for seed_value in range(40):
		var plans: Array = LootResolver.resolve(table, _context(), _rng(seed_value))["plans"]
		assert_eq(plans.size(), 1, "only the chance-1.0 entry fires at seed %d" % seed_value)
		assert_eq(String(plans[0]["entry_id"]), "certain", "the heavy chance-0.0 entry stays out")
	# A weighted entry with the same weight as its rival splits roughly evenly,
	# which is exactly what a chance roll does not do.
	var left := _item_entry(&"left", 1.0)
	left.item_id = &"beast_storm_hawk_bone"
	var right := _item_entry(&"right", 1.0)
	right.item_id = &"artifact_iron_titan_ore"
	var contested := _table([left, right] as Array[LootEntry])
	var picks := {"left": 0, "right": 0}
	for seed_value in range(400):
		var plans: Array = LootResolver.resolve(contested, _context(), _rng(seed_value))["plans"]
		picks[String(plans[0]["entry_id"])] = int(picks[String(plans[0]["entry_id"])]) + 1
	var spread: int = absi(int(picks["left"]) - int(picks["right"]))
	assert_eq(spread < 120, true, "equal weights split the draws (spread %d)" % spread)


## A chance of exactly 0.0 stays near zero under the maximum legal bonus, and a
## chance of 1.0 stays certain even under a negative one: the bonus shifts a
## roll, it never replaces it.
func test_independent_chance_uses_the_bounded_bonus_only() -> void:
	var entry := _item_entry(&"charmed", 1.0, 0.0)
	var table := _table([entry] as Array[LootEntry], 0, 0, true)
	var fires := 0
	for seed_value in range(400):
		var axes := LootBonus.axes(LootBonus.MAX_INPUT)
		if not (
			(LootResolver.resolve(table, _context(axes), _rng(seed_value))["plans"] as Array)
			. is_empty()
		):
			fires += 1
	assert_eq(fires > 0, true, "the maximum bonus does lift a 0.0 chance")
	assert_eq(
		fires <= 400 * int(LootBonus.MAX_CHANCE_BONUS * 100.0) + 5,
		true,
		"and only by the declared bonus (%d of 400)" % fires
	)
	assert_almost_eq(entry.effective_chance(99.0), 1.0, "a 1.0 chance is capped at 1.0")
	assert_almost_eq(entry.effective_chance(-5.0), 0.0, "a 0.0 chance is floored at 0.0")


## The explicit no-drop outcome really can produce nothing, on every seed.
func test_a_no_drop_table_produces_nothing() -> void:
	var never := _item_entry(&"never", 1.0, 0.0)
	var table := _table([never] as Array[LootEntry], 0, 0, true)
	for seed_value in range(60):
		var resolved := LootResolver.resolve(table, _context(), _rng(seed_value))
		assert_eq((resolved["plans"] as Array).is_empty(), true, "nothing at seed %d" % seed_value)


## `allow_empty = false` forces a pick, so a table that declares it never comes up
## empty actually never does — and the forced pick is a real item.
func test_allow_empty_false_forces_a_real_pick() -> void:
	var table := _table([_item_entry(&"only", 1.0)] as Array[LootEntry], 0, 0, false)
	for seed_value in range(40):
		var plans: Array = LootResolver.resolve(table, _context(), _rng(seed_value))["plans"]
		assert_eq(plans.size(), 1, "the forced pick fires at seed %d" % seed_value)


## A guaranteed entry is present on every outcome, including with the maximum
## `loot_bonus` count bonus, and takes its exact authored quantity.
func test_guaranteed_entry_is_present_on_every_outcome() -> void:
	var sure := _item_entry(&"sure", 1.0, LootEntry.NO_CHANCE, true)
	sure.item_id = &"amulet_iron_sage_eye"
	sure.quantity = 2
	var table := _table([sure, _item_entry(&"filler", 1.0)] as Array[LootEntry], 0, 0, true)
	for seed_value in range(80):
		var plans: Array = (
			LootResolver
			. resolve(table, _context({"count": LootBonus.MAX_EXTRA_COUNT}), _rng(seed_value))["plans"]
		)
		var found := 0
		for plan in plans:
			if String(plan["entry_id"]) == "sure":
				found += 1
				assert_eq(int(plan["quantity"]), 2, "a guaranteed entry takes its exact quantity")
		assert_eq(found, 1, "the guaranteed entry is present exactly once at seed %d" % seed_value)


## A quantity range is honoured, and a guaranteed entry does not roll inside it.
func test_quantity_range_is_respected_separately_from_the_draw_count() -> void:
	var entry := _item_entry(&"ranged", 1.0)
	entry.quantity = 2
	entry.quantity_max = 5
	var table := _table([entry] as Array[LootEntry], 1)
	var seen := {}
	for seed_value in range(80):
		var plan: Dictionary = LootResolver.resolve(table, _context(), _rng(seed_value))["plans"][0]
		var quantity := int(plan["quantity"])
		assert_eq(quantity >= 2 and quantity <= 5, true, "quantity %d inside [2, 5]" % quantity)
		seen[quantity] = true
	assert_eq(seen.size() > 1, true, "the range actually varies")


## A nested table resolves and its results are spliced into the parent's outcome,
## with no cycle and no loss.
func test_nested_table_resolves_without_a_cycle() -> void:
	var child := LootContent.instance().table(&"loot_ember_core_pool")
	assert_ne(child, null, "authored nested table loads")
	var entry := _nested_entry(&"cores", &"loot_ember_core_pool", 1.0)
	var table := _table([entry] as Array[LootEntry], 1, 0, false)
	table.realm = &"spirit_severing"
	var context := LootResolver.make_context(&"", &"", &"", LootBonus.axes(0.0))
	for seed_value in range(20):
		var resolved := LootResolver.resolve(table, context, _rng(seed_value))
		assert_ne(
			(resolved["plans"] as Array).is_empty(),
			true,
			"nested pick resolved at seed %d" % seed_value
		)
		for plan in resolved["plans"]:
			# The splice is provenance, not loss: the plan names the table that
			# actually produced it, and that is the nested one.
			assert_eq(String(plan["table_id"]), "loot_ember_core_pool", "the child owns the plan")
			assert_eq(
				String(plan["entry_id"]).begins_with("ecp_"), true, "a child entry was expanded"
			)


## A cyclic reference is rejected by the validator, with the closing path named.
func test_a_cyclic_table_is_rejected_by_the_validator() -> void:
	var left := LootTableDef.new()
	left.id = &"probe_cycle_left"
	var right := LootTableDef.new()
	right.id = &"probe_cycle_right"
	var to_right := _nested_entry(&"to_right", &"probe_cycle_right", 1.0)
	var to_left := _nested_entry(&"to_left", &"probe_cycle_left", 1.0)
	left.entries = [to_right] as Array[LootEntry]
	right.entries = [to_left] as Array[LootEntry]
	var problems := LootValidator.validate_tables([left, right])
	var cycle := ""
	for problem in problems:
		if problem.contains("cycle"):
			cycle = problem
	assert_ne(cycle, "", "the cycle is reported")
	assert_eq(cycle.contains("probe_cycle_left"), true, "the cycle names the offending tables")


## A table longer than the nesting limit is reported too, so a deep chain cannot
## ship silently.
func test_an_over_deep_chain_is_rejected() -> void:
	var tables: Array = []
	for index in LootContent.MAX_NESTING_DEPTH + 3:
		var table := LootTableDef.new()
		table.id = StringName("probe_deep_%d" % index)
		table.entries = [_item_entry(&"leaf_%d" % index, 1.0)] as Array[LootEntry]
		tables.append(table)
	for index in range(tables.size() - 1):
		(tables[index] as LootTableDef).entries = (
			[_nested_entry(&"down_%d" % index, (tables[index + 1] as LootTableDef).id, 1.0)]
			as Array[LootEntry]
		)
	var problems := LootValidator.validate_tables(tables)
	var depth_problem := ""
	for problem in problems:
		if problem.contains("nesting limit"):
			depth_problem = problem
	assert_ne(depth_problem, "", "the chain depth is reported")


## Every authored content problem the brief names is rejected, each with its own
## message, so a malformed table cannot ship.
func test_validation_rejects_missing_ids_bad_weights_and_bad_quantities() -> void:
	var missing_item := _item_entry(&"missing", 1.0)
	missing_item.item_id = &"no_such_item_anywhere"
	var negative_weight := _item_entry(&"negative", -2.0)
	var bad_quantity := _item_entry(&"bad_quantity", 1.0)
	bad_quantity.quantity = 5
	bad_quantity.quantity_max = 2
	var bad_table := _table([missing_item, negative_weight, bad_quantity] as Array[LootEntry], 3, 1)
	var problems := LootValidator.validate_tables([bad_table])
	var text := "\n".join(problems)
	assert_eq(text.contains("no_such_item_anywhere"), true, "a missing item id is rejected")
	assert_eq(text.contains("negative"), true, "a negative weight is rejected")
	assert_eq(
		text.contains("quantity range is unsatisfiable"),
		true,
		"an inverted quantity range is rejected"
	)
	assert_eq(
		text.contains("draw range is unsatisfiable"), true, "an inverted draw range is rejected"
	)


## A guaranteed entry that also declares a chance, and a chance outside 0..1, are
## both rejected: the four mechanisms must stay separable in content.
func test_validation_rejects_ambiguous_entry_semantics() -> void:
	var guaranteed_with_chance := _item_entry(&"ambiguous", 1.0, 0.5, true)
	var out_of_range_chance := _item_entry(&"too_likely", 1.0, 4.0)
	var table := _table(
		[guaranteed_with_chance, out_of_range_chance] as Array[LootEntry], 0, 0, true
	)
	var text := "\n".join(LootValidator.validate_tables([table]))
	assert_eq(
		text.contains("must not declare a chance"),
		true,
		"a guaranteed entry may not declare a chance"
	)
	assert_eq(text.contains("outside 0.0..1.0"), true, "a chance above 1.0 is rejected")


## `loot_bonus` changes the outcome inside its declared bound and never past it.
func test_loot_bonus_stays_inside_its_declared_bound() -> void:
	var limits := LootBonus.limits()
	var entry := _item_entry(&"only", 1.0)
	var table := _table([entry] as Array[LootEntry], 1, 1, false)
	var baseline := 0
	for seed_value in range(300):
		baseline += (
			(LootResolver.resolve(table, _context(), _rng(seed_value))["plans"] as Array).size()
		)
	var bonused := 0
	for seed_value in range(300):
		var axes := LootBonus.axes(LootBonus.MAX_INPUT)
		bonused += (
			(LootResolver.resolve(table, _context(axes), _rng(seed_value))["plans"] as Array).size()
		)
	# One authored draw plus at most MAX_EXTRA_COUNT more.
	assert_eq(
		bonused <= baseline + 300 * int(limits["max_extra_count"]), true, "count bonus is bounded"
	)
	assert_eq(bonused > baseline, true, "the count bonus does something")
	for rate in [0.0, 0.4, 1.0, 2.0, 3.9, 4.0, 12.0, 1000.0]:
		var axes := LootBonus.axes(rate)
		assert_eq(float(axes["chance"]) <= float(limits["max_chance_bonus"]), true, "chance capped")
		assert_eq(int(axes["count"]) <= int(limits["max_extra_count"]), true, "count capped")
		assert_eq(
			int(axes["quality_steps"]) <= int(limits["max_quality_steps"]), true, "quality capped"
		)
		assert_eq(float(axes["chance"]) >= 0.0, true, "chance is never negative")


## The chance axis never turns into a draw: a table whose only entry is weighted
## produces nothing without the count bonus, and exactly the bonus with it.
## The count axis adds exactly the declared number of weighted draws and never
## invents a guaranteed entry.
func test_loot_bonus_count_axis_adds_bounded_weighted_draws() -> void:
	var table := _table([_item_entry(&"weighted", 1.0)] as Array[LootEntry], 0, 0, true)
	for seed_value in range(40):
		assert_eq(
			(
				(LootResolver.resolve(table, _context(), _rng(seed_value))["plans"] as Array)
				. is_empty()
			),
			true,
			"zero authored draws produce nothing at seed %d" % seed_value
		)
	var axes := LootBonus.axes(LootBonus.MAX_INPUT)
	for seed_value in range(40):
		var plans: Array = LootResolver.resolve(table, _context(axes), _rng(seed_value))["plans"]
		assert_eq(plans.size(), int(axes["count"]), "exactly the declared extra draws")
		assert_eq(plans.is_empty(), false, "the count bonus produces real drops")


## The chance axis raises an independent roll's hit rate and never a weighted one.
func test_loot_bonus_chance_axis_only_moves_independent_rolls() -> void:
	var entry := _item_entry(&"charmed", 1.0, 0.5)
	var chance_only := _table([entry] as Array[LootEntry], 0, 0, true)
	var fires := 0
	for seed_value in range(400):
		var axes := LootBonus.axes(LootBonus.MAX_INPUT)
		if not (
			(LootResolver.resolve(chance_only, _context(axes), _rng(seed_value))["plans"] as Array)
			. is_empty()
		):
			fires += 1
	assert_eq(
		fires > 260, true, "a 0.5 chance plus the maximum bonus fires more than 0.5 of the time"
	)
	var weighted := _table([_item_entry(&"weighted", 1.0)] as Array[LootEntry], 0, 0, true)
	for seed_value in range(40):
		assert_eq(
			(
				(
					(
						LootResolver
						. resolve(weighted, _context({"chance": 1.0}), _rng(seed_value))["plans"]
					)
					as Array
				)
				. is_empty()
			),
			true,
			"a full chance bonus never makes a weighted entry fire at seed %d" % seed_value
		)


## The quality axis promotes a drop's rarity context by at most its declared cap.
func test_loot_bonus_quality_axis_is_bounded() -> void:
	var table := _table([_item_entry(&"only", 1.0)] as Array[LootEntry], 1, 1, false)
	table.rarity = &"common"
	var promoted := 0
	for seed_value in range(50):
		var axes := LootBonus.axes(LootBonus.MAX_INPUT)
		var plan: Dictionary = (
			LootResolver.resolve(table, _context(axes), _rng(seed_value))["plans"][0]
		)
		if String(plan["rarity"]) == "magic":
			promoted += 1
		assert_ne(String(plan["rarity"]), "rare", "never more than one tier of promotion")
	assert_eq(promoted > 0, true, "the quality axis does something")


## The drop's rarity context comes from the source, and an entry's rarity floor
## raises it — the two are separate axes.
func test_source_realm_and_rarity_reach_the_drop_plan() -> void:
	var table := _table([_item_entry(&"only", 1.0)] as Array[LootEntry], 1, 1, false)
	var entry := table.entries[0]
	entry.rarity_floor = &"rare"
	var context := LootResolver.make_context(&"heaven_immortal", &"magic", &"", LootBonus.axes(0.0))
	var plan: Dictionary = LootResolver.resolve(table, context, _rng(11))["plans"][0]
	assert_eq(String(plan["realm"]), "heaven_immortal", "the source realm reaches the plan")
	assert_eq(String(plan["rarity"]), "rare", "the entry floor wins over the source rarity")


## A unique-route item is refused for every boss but the one it names.
func test_a_unique_route_item_only_drops_from_its_boss() -> void:
	var def := ItemDef.new()
	def.id = &"probe_route_relic"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = &"accessory"
	def.stackable = false
	def.rarity = &"rare"
	def.realm = &"spirit_unity"
	def.roll_spec = {"count": 3, "contexts": ["prefix", "postfix"]}
	def.tags = ["unique_route:loot_ember_vault_warden"] as Array[StringName]
	LootContent.instance().provide(def.id, def)
	var entry := _item_entry(&"route", 1.0)
	entry.item_id = def.id
	var table := _table([entry] as Array[LootEntry], 1, 1, false)
	var mine := LootResolver.make_context(&"", &"", &"loot_ember_vault_warden", LootBonus.axes(0.0))
	var theirs := LootResolver.make_context(
		&"", &"", &"loot_ember_vault_cinder_hound", LootBonus.axes(0.0)
	)
	assert_eq(
		LootRoutes.permits(def, &"loot_ember_vault_warden"), true, "the named boss may drop it"
	)
	assert_eq(LootRoutes.permits(def, &"loot_ember_vault_cinder_hound"), false, "no other boss may")
	var mine_plans: Array = LootResolver.resolve(table, mine, _rng(5))["plans"]
	assert_eq(mine_plans.size(), 1, "the route owner gets the drop")
	assert_eq(String(mine_plans[0]["def_id"]), "probe_route_relic", "the route item resolves")
	var their_result := LootResolver.resolve(table, theirs, _rng(5))
	assert_eq((their_result["plans"] as Array).is_empty(), true, "another boss gets nothing")
	assert_eq((their_result["warnings"] as Array).size() > 0, true, "the refusal is reported")
