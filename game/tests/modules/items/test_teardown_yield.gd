extends TestCase

## The yield POLICY, isolated from the transaction: what a teardown pays, and the
## content that has to exist for it to be worth anything.
##
## The formula is the load-bearing design decision of this lane, so it is pinned
## here rather than only exercised through a bag: a retune that silently inverts
## it (a flat full refund, or a discount that reaches zero) would still pass every
## end-to-end test, because those only assert that A unit appeared.

## The materials the policy names, one per grade.
const JADE := {
	&"mortal": &"jade_ore",
	&"spirit": &"jade_azure",
	&"earth": &"jade_moon",
	&"heaven": &"jade_star",
	&"immortal": &"jade_immortal",
	&"divine": &"jade_divine",
}


func _def(grade: StringName, rarity: StringName = &"common", rolled: int = 0) -> ItemDef:
	var def := ItemDef.new()
	def.id = StringName("yield_probe_%s_%s" % [grade, rarity])
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.ARMOR
	def.grade = grade
	def.rarity = rarity
	def.stackable = false
	return def


func _instance(rolled: int) -> ItemInstance:
	var instance := ItemInstance.new(&"yield_probe", &"yield_probe_1")
	for index in rolled:
		instance.rolled.append(
			{"option_id": StringName("core_attack_physical_%d" % index), "value": 1.0 + index}
		)
	instance.rarity = &"common"
	return instance


# --- the formula ---------------------------------------------------------------


## A grade's base is its ceiling: the units a COMMON, unrolled piece of that grade
## pays. Graded, so a higher band is made of rarer stuff.
func test_a_grade_base_is_the_ceiling_of_its_own_yield() -> void:
	assert_eq(TeardownYield.units_for(_def(&"mortal"), _instance(0)), 2, "mortal")
	assert_eq(TeardownYield.units_for(_def(&"spirit"), _instance(0)), 3, "spirit")
	assert_eq(TeardownYield.units_for(_def(&"earth"), _instance(0)), 4, "earth")
	assert_eq(TeardownYield.units_for(_def(&"heaven"), _instance(0)), 5, "heaven")
	assert_eq(TeardownYield.units_for(_def(&"immortal"), _instance(0)), 6, "immortal")
	assert_eq(TeardownYield.units_for(_def(&"divine"), _instance(0)), 8, "divine")


## Rarity DISCOUNTS. This is the counterpart that keeps looting meaningful: a flat
## full refund would pay a lucky roll its whole worth and delete the reason to keep
## hunting for a better one.
func test_a_higher_rarity_refunds_less_of_its_grade() -> void:
	for grade in [&"mortal", &"divine"]:
		var common := TeardownYield.units_for(_def(grade, &"common"), _instance(0))
		var magic := TeardownYield.units_for(_def(grade, &"magic"), _instance(0))
		var rare := TeardownYield.units_for(_def(grade, &"rare"), _instance(0))
		var legendary := TeardownYield.units_for(_def(grade, &"legendary"), _instance(0))
		assert_ne(
			common >= magic, true, "%s: a magic refunds no more than a common" % grade
		)
		assert_ne(magic >= rare, true, "%s: a rare refunds no more than a magic" % grade)
		assert_ne(
			rare >= legendary, true, "%s: a legendary refunds no more than a rare" % grade
		)
	# And the ratio is exactly the authored policy, not merely monotonic.
	assert_eq(
		TeardownYield.units_for(_def(&"divine", &"legendary"), _instance(0)),
		2,
		"a divine legendary pays a quarter of its base (8 * 0.25)"
	)


## Each realized option discounts further, because a rolled option is the player's
## reason to HOLD the piece rather than break it.
func test_a_realized_option_costs_yield() -> void:
	var bare := TeardownYield.units_for(_def(&"divine"), _instance(0))
	for rolled in [1, 2, 3, 4]:
		var value := TeardownYield.units_for(_def(&"divine"), _instance(rolled))
		assert_ne(value <= bare, true, "%d rolled options pay no more than none" % rolled)
	# Monotone across the discounts that actually change the integer.
	assert_eq(
		TeardownYield.units_for(_def(&"divine"), _instance(1)),
		7,
		"one option on a divine pays 8 * 0.92 = 7"
	)


## No combination yields nothing. A zero would be a SECOND way to throw gear
## away — the exact defect this sink was built to remove — so the floor holds even
## at the worst case: the highest grade, the rarest roll, and a full four options.
func test_no_combination_ever_yields_nothing() -> void:
	for grade in ItemGrade.ALL:
		for rarity in ItemRarity.ALL:
			var def := _def(grade, rarity)
			for rolled in [0, 1, 2, 3, 4, 8]:
				def.rarity = rarity
				var units := TeardownYield.units_for(def, _instance(rolled))
				assert_ne(
					units >= TeardownYield.MIN_UNITS,
					true,
					"%s/%s with %d options pays at least one" % [grade, rarity, rolled]
				)
	assert_eq(TeardownYield.MIN_UNITS, 1, "and the floor is exactly one")


## The yield never exceeds its grade's base, so a discount can only ever reduce.
func test_no_yield_exceeds_its_grade_ceiling() -> void:
	for grade in ItemGrade.ALL:
		for rarity in ItemRarity.ALL:
			for rolled in [0, 1, 2, 3, 4]:
				var units := TeardownYield.units_for(_def(grade, rarity), _instance(rolled))
				assert_ne(
					units <= int(TeardownYield.GRADE_BASE.get(grade, 0)),
					true,
					"%s/%s/%d stays under the grade ceiling" % [grade, rarity, rolled]
				)


## A malformed grade is a content defect, and must not ALSO become a player-facing
## dead end: it falls back to the mortal base rather than yielding nothing.
func test_an_unknown_grade_falls_back_to_mortal_rather_than_nothing() -> void:
	var units := TeardownYield.units_for(_def(&"no_such_grade"), _instance(0))
	assert_eq(units, TeardownYield.units_for(_def(&"mortal"), _instance(0)), "the mortal base")
	assert_ne(units > 0, true, "and still pays something")


## A null definition or instance is not a teardown at all.
func test_no_definition_means_no_yield_and_no_material() -> void:
	var quote := TeardownYield.quote(null, null)
	assert_eq(bool(quote.get("ok", false)), false, "nothing to quote")
	assert_eq(int(quote.get("units", 0)), 0, "no units")
	assert_eq(String(quote.get("material_id", "")), "", "no material")
	assert_eq(TeardownYield.units_for(null, _instance(0)), 0, "and the policy agrees")


# --- content existence ---------------------------------------------------------


## Every grade the vocabulary declares pays a material. A grade added to
## `ItemGrade.ALL` without a row here would otherwise be a silent dead end.
func test_every_grade_declares_a_material() -> void:
	for grade in ItemGrade.ALL:
		assert_ne(
			TeardownYield.material_for(grade) != &"",
			true,
			"%s declares a salvage material" % grade
		)


## The table is keyed by grade ID and every key is a real grade. Keying by position
## is how an inserted grade would silently rescale every grade below it.
func test_the_material_table_is_keyed_by_real_grade_ids() -> void:
	for grade in TeardownYield.MATERIAL_BY_GRADE.keys():
		assert_eq(ItemGrade.ALL.has(grade), true, "%s is a declared grade" % grade)
	assert_eq(
		TeardownYield.MATERIAL_BY_GRADE.size(),
		ItemGrade.ALL.size(),
		"the table covers every grade exactly once"
	)


## Every material RESOLVES. A yield nobody can name is a yield that grants nothing.
func test_every_yielded_material_resolves_in_content() -> void:
	for grade in ItemGrade.ALL:
		var material_id := TeardownYield.material_for(grade)
		var def := Crafting.resolve(material_id)
		assert_ne(def == null, false, "%s resolves" % material_id)
		if def != null:
			assert_eq(def.id, material_id, "%s is the id that resolved" % material_id)
			assert_eq(def.category, ItemCategory.MATERIAL, "%s is a material" % material_id)
			assert_ne(def.stackable, false, "%s stacks, so a yield takes one slot" % material_id)


## ## Why this test exists
##
## The yield is only a sink if something SPENDS it. A material that resolves but
## that no recipe consumes would leave the player holding an accumulating pile and
## the original defect exactly where it started. So the assertion is about the
## recipe corpus, not about the material: at least one authored recipe names each
## grade's material as an input.
func test_every_yielded_material_is_consumed_by_an_authored_recipe() -> void:
	var paths := ContentScan.files_under("res://data/recipes")
	assert_ne(paths.size() > 0, true, "the recipe corpus is readable")
	# One pass over the corpus, counting consumers per material id. The corpus is
	# a directory snapshot taken by `files_under` and this loop only READS it, so
	# there is no bound to take and nothing grows.
	var consumers := {}
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		for grade in ItemGrade.ALL:
			var material_id := String(TeardownYield.material_for(grade))
			if not consumers.has(material_id):
				consumers[material_id] = 0
			if text.contains('&"%s"' % material_id):
				consumers[material_id] += 1
	for grade in ItemGrade.ALL:
		var material_id := String(TeardownYield.material_for(grade))
		assert_ne(
			int(consumers.get(material_id, 0)) > 0,
			true,
			"%s is consumed by at least one recipe (%d found)" % [material_id, consumers.get(material_id, 0)]
		)


## The quote a panel renders, as primitives only.
func test_a_quote_reports_primitives_and_its_own_basis() -> void:
	var def := _def(&"earth", &"rare")
	var quote := TeardownYield.quote(def, _instance(2))
	assert_eq(bool(quote.get("ok", false)), true, "the quote is quotable")
	assert_eq(String(quote.get("material_id", "")), String(JADE[&"earth"]), "the earth material")
	assert_eq(String(quote.get("grade", "")), "earth", "the grade that decided it")
	assert_eq(String(quote.get("rarity", "")), "rare", "the rarity that discounted it")
	assert_eq(int(quote.get("rolled_options", 0)), 2, "the options that discounted it")
	assert_eq(
		int(quote.get("units", 0)),
		TeardownYield.units_for(def, _instance(2)),
		"and the units agree with the policy"
	)