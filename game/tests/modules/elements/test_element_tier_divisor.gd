extends TestCase

## ADR 0069's tier-2 dominance fix and BL-0938's mastery bond, asserted as a SHAPE
## rather than as a restatement of a number. `combat_engine/test_qi_damage_realm.gd`
## pins the same contract from the damage side; this suite pins it from the provider's
## own vocabulary — `TIER_MASTERY_STEP`, `POWER_CEILING`, `ElementMastery.MASTERY_HALF`,
## `ElementStats.BASE_ELEMENTS` — so a retune of the step or the ceiling does not require
## walking into another module's suite to find out.
##
## The reference implementation, written out in the test rather than reusing
## `ElementProvider`'s own helpers. That is the whole point of a shape test: it must pin
## the CONTRACT (a saturating ceiling `C * m / (m + HALF)`, taxed by the tier divisor and
## nothing else), not call the code under test and declare the result correct. A test
## that delegated would pass whatever the provider did.
const BASE_MASTERY_CEILING := 3.0

## The saturation half, written out for the same reason: the contract is `m / (m + 300)`.
const BASE_MASTERY_HALF := 300.0


func _ceiling_term(mastery: float) -> float:
	if mastery <= 0.0:
		return 0.0
	return BASE_MASTERY_CEILING * mastery / (mastery + BASE_MASTERY_HALF)


func _divisor(tier: int) -> float:
	return 1.0 + float(tier - 1) * ElementProvider.TIER_MASTERY_STEP


func _power(rules: ElementRules, element: StringName, affinity: float, mastery: float) -> float:
	var actor := Actor.new(&"shape", {ElementStats.mastery_id(element): mastery})
	actor.set_affinity(element, affinity)
	ElementsApi.attach(actor, rules)
	return actor.stats.derived(ElementStats.power_id(element))


# --- tier 1 pays the full ceiling ----------------------------------------------------


## TIER 1 PAYS THE FULL CEILING. The divisor is exactly `1.0` at tier 1, so the
## contribution is `affinity * (1 + C * m / (m + HALF))` to float precision and nothing
## else — asserted tight because this is the half of the population that must carry the
## bond's whole mastery term.
func test_tier_one_element_power_pays_the_full_ceiling() -> void:
	var rules := ElementsApi.default_rules()
	for element in ElementStats.BASE_ELEMENTS:
		for mastery in [0.0, 1.0, 5.0, 9.0, 50.0]:
			assert_almost_eq(
				_power(rules, element, 10.0, mastery),
				10.0 * (1.0 + _ceiling_term(mastery)),
				(
					"%s at mastery %s must be exactly the untaxed saturated figure"
					% [element, mastery]
				),
				1e-9
			)


## The same claim from the divisor's own arithmetic: at tier 1 the divisor is exactly
## `1.0` and therefore the whole ceiling is paid, so the two sides of the contract agree
## BEFORE any actor is built. A tier-1 element whose `ElementDef` had drifted off tier 1
## would be caught by the case above; this is the diagnostic.
func test_the_tier_one_divisor_is_exactly_one_and_pays_no_tax() -> void:
	assert_eq(_divisor(1), 1.0, "tier 1 divides by exactly 1.0")
	assert_eq(
		BASE_MASTERY_CEILING / _divisor(1),
		BASE_MASTERY_CEILING,
		"and so its mastery ceiling is exactly the number the provider declares"
	)


# --- tier 2 is strictly reduced -----------------------------------------------------


## TIER 2 PAYS. Strictly less than the same affinity and mastery in tier 1, and exactly
## the taxed figure. `assert_almost_eq` on the taxed value with a tight epsilon because
## the divisor is a division and therefore genuinely not a clean binary fraction.
func test_tier_two_element_power_is_strictly_reduced_by_the_divisor() -> void:
	var rules := ElementsApi.default_rules()
	for element in ElementStats.ADVANCED_ELEMENTS:
		var taxed := _power(rules, element, 10.0, 5.0)
		var untaxed := 10.0 * (1.0 + _ceiling_term(5.0))
		assert_almost_eq(
			taxed,
			10.0 * (1.0 + _ceiling_term(5.0) / _divisor(2)),
			"%s pays exactly the tier-2 divisor" % element,
			1e-6
		)
		assert_eq(
			taxed < untaxed,
			true,
			"%s read %s, which is not strictly below the untaxed %s" % [element, taxed, untaxed]
		)


## THE SHAPE, as a measured relationship rather than a restated constant: the tier-2
## tax is the same fraction on every advanced element, and it is read where the ceiling
## is REAL (saturation 0.5) rather than at a mastery the saturating curve makes nearly
## free. A band rather than a pinned figure, so retuning `TIER_MASTERY_STEP` stays a
## balance decision rather than a test failure.
func test_the_tier_two_tax_is_one_relationship_across_every_advanced_element() -> void:
	var rules := ElementsApi.default_rules()
	var ratios: Array[float] = []
	for element in ElementStats.ADVANCED_ELEMENTS:
		var taxed := _power(rules, element, 10.0, 300.0)
		var untaxed := 10.0 * (1.0 + _ceiling_term(300.0))
		ratios.append(taxed / untaxed)
	var lowest: float = ratios.min()
	var highest: float = ratios.max()
	assert_almost_eq(
		lowest,
		highest,
		"the tax is a property of the TIER, so every advanced element pays the same one",
		1e-9
	)
	# And the size of that one tax, as a band on the whole contribution rather than a
	# restated constant. The divisor rides the MASTERY term, so at saturation 0.5 the
	# mastery term is 1.5 and the observed ratio is the 9.09% cut on it diluted by the
	# untaxed affinity of 10.0.
	assert_eq(
		lowest > 0.85 and lowest < 1.0,
		true,
		"the tier-2 tax is a real but partial cut on the whole contribution; read %s" % lowest
	)
	assert_eq(
		BASE_MASTERY_CEILING / _divisor(2) < BASE_MASTERY_CEILING,
		true,
		"and on the mastery term alone the cut is strict, which is the shape that matters"
	)


# --- tier 3 pays the same tax one step further ---------------------------------------


## ADR 0921's triad is tier 3, so it carries the divisor one step past the advanced ten:
## exactly the taxed figure, and strictly below tier 2's for the same numbers. Asserted
## as a relationship rather than a pinned constant, so retuning `TIER_MASTERY_STEP`
## stays a balance decision.
func test_tier_three_element_power_is_strictly_reduced_again() -> void:
	var rules := ElementsApi.default_rules()
	for element in ElementStats.TIER_THREE_ELEMENTS:
		var tier_three := _power(rules, element, 10.0, 5.0)
		var tier_two := 10.0 * (1.0 + _ceiling_term(5.0) / _divisor(2))
		assert_almost_eq(
			tier_three,
			10.0 * (1.0 + _ceiling_term(5.0) / _divisor(3)),
			"%s pays exactly the tier-3 divisor" % element,
			1e-6
		)
		assert_eq(
			tier_three < tier_two,
			true,
			(
				"%s read %s, which is not strictly below the tier-2 %s"
				% [element, tier_three, tier_two]
			)
		)


# --- the tax rides the MASTERY term, never the affinity ----------------------------


## THE INVARIANT THE TAX EXISTS TO PROTECT: zero mastery pays NOTHING at any tier. If
## the tax were applied to the whole expression, an advanced element with no mastery
## would read `affinity * (1/1.1)` — a trainer who has invested nothing paying a
## permanent penalty. Asserted exactly, because at zero mastery the figure must be the
## affinity to the bit.
func test_zero_mastery_pays_no_tax_at_any_tier() -> void:
	var rules := ElementsApi.default_rules()
	var every_element: Array = (
		ElementStats.BASE_ELEMENTS
		+ ElementStats.ADVANCED_ELEMENTS
		+ ElementStats.TIER_THREE_ELEMENTS
	)
	for element in every_element:
		assert_almost_eq(
			_power(rules, element, 10.0, 0.0),
			10.0,
			"%s with zero mastery is exactly its affinity at every tier" % element,
			1e-9
		)


## Mastery is the ONLY thing the divisor touches, so the tax scales WITH the mastery
## term: the absolute saving between tier 1 and tier 2 must itself grow with mastery.
## A divisor applied anywhere else would produce a saving that shrinks, or one that is
## constant.
func test_the_saving_from_the_tax_grows_with_mastery() -> void:
	var rules := ElementsApi.default_rules()
	var previous_saving := -1.0
	for mastery in [0.0, 2.0, 6.0, 12.0, 30.0]:
		var base := _power(rules, ElementStats.FIRE, 10.0, mastery)
		var advanced := _power(rules, ElementStats.LIGHTNING, 10.0, mastery)
		var saving := base - advanced
		assert_eq(
			saving >= previous_saving,
			true,
			(
				"the tier-2 saving must not shrink as mastery grows; read %s at mastery %s"
				% [saving, mastery]
			)
		)
		previous_saving = saving
	assert_eq(
		previous_saving > 0.0,
		true,
		"and by the top of the ladder the tax is costing something real"
	)


## MONOTONICITY at every tier: the property the tax must not be able to break. ADR 0069
## states it as "the tax changes what tier 2 costs, never whether mastery pays", and a
## divider that ever reached the affinity would make a high-mastery advanced element
## read BELOW its own baseline.
func test_mastery_still_pays_at_every_tier_so_no_actor_loses_power_by_levelling() -> void:
	var rules := ElementsApi.default_rules()
	for element in ElementStats.BASE_ELEMENTS + ElementStats.ADVANCED_ELEMENTS:
		var untrained := _power(rules, element, 10.0, 0.0)
		var trained := _power(rules, element, 10.0, 25.0)
		assert_eq(
			trained > untrained,
			true,
			(
				(
					"%s read %s trained against %s untrained — a divider that reached the "
					+ "affinity would make levelling a LOSS"
				)
				% [element, trained, untrained]
			)
		)


# --- the fail-safe ------------------------------------------------------------------


## A tier is an authored integer and `ElementMastery.MAX_ELEMENT_TIER` is 3, but the
## tax must not be able to produce a non-finite or negative contribution from a
## malformed def — a NaN here would poison `element_power_<e>` for every actor carrying
## the provider, which is the failure mode `ElementProvider._tier_divisor` documents.
func test_a_malformed_tier_resolves_to_no_tax_and_never_a_non_finite_power() -> void:
	var rules := ElementsApi.default_rules()
	for tier in [-5, 0, 1, ElementMastery.MAX_ELEMENT_TIER, 50]:
		var def := ElementDef.new()
		def.id = &"odd_element"
		def.tier = tier
		var solo := ElementRules.new([def] as Array[ElementDef])
		var power := _power(solo, &"odd_element", 10.0, 8.0)
		assert_eq(
			is_finite(power) and power >= 0.0,
			true,
			"tier %s produced %s, which must be a finite non-negative magnitude" % [tier, power]
		)
	# An element the rules do not define at all reads as tier 1 — the shape nobody
	# authored, and the same fail-safe as every other null read in the module.
	var power := _power(rules, &"not_an_element", 10.0, 8.0)
	assert_almost_eq(
		power,
		0.0,
		"an element outside the rules set contributes nothing rather than throwing",
		1e-9
	)


## The divisor is a CONSTANT OF THE POLICY and therefore a named, tunable figure rather
## than a literal buried in the arithmetic. Pinned as a range, not as a value: a
## balance pass must be able to move it, and what must not be possible is for it to
## become `0.0` (which would divide by zero) or negative (which would INVERT the
## mastery term and make levelling a loss).
func test_the_step_is_a_usable_tuning_knob_that_cannot_break_the_arithmetic() -> void:
	assert_eq(
		ElementProvider.TIER_MASTERY_STEP > 0.0,
		true,
		"a zero step is a divisor of 1.0 and a tax that never applies; raise it, not zero it"
	)
	assert_eq(
		_divisor(ElementMastery.MAX_ELEMENT_TIER) > 1.0,
		true,
		"the top tier this module supports must actually pay more than tier 1"
	)
	var rules := ElementsApi.default_rules()
	var top := _power(rules, ElementStats.LIGHTNING, 10.0, 10.0)
	assert_eq(
		is_finite(top) and top > 0.0,
		true,
		"and the shipped step leaves tier 2 on a finite positive magnitude, read %s" % top
	)
