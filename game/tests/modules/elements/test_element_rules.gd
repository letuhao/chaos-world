extends TestCase

## ADR 0004: generating (相生) and overcoming (相克) drive the element matchup.


func _rules() -> ElementRules:
	return ElementRules.new(ElementDefaults.all())


func test_overcome_is_strong() -> void:
	var rules := _rules()
	assert_almost_eq(rules.multiplier(ElementStats.METAL, ElementStats.WOOD), 1.5, "metal > wood")
	assert_almost_eq(rules.multiplier(ElementStats.FIRE, ElementStats.METAL), 1.5, "fire > metal")


func test_overcome_by_is_weak() -> void:
	var rules := _rules()
	assert_almost_eq(rules.multiplier(ElementStats.WOOD, ElementStats.METAL), 0.5, "wood < metal")
	assert_almost_eq(rules.multiplier(ElementStats.METAL, ElementStats.FIRE), 0.5, "metal < fire")


func test_generating_nourishes() -> void:
	var rules := _rules()
	assert_almost_eq(
		rules.multiplier(ElementStats.METAL, ElementStats.WATER), 0.75, "metal feeds water"
	)
	assert_almost_eq(
		rules.multiplier(ElementStats.FIRE, ElementStats.EARTH), 0.75, "fire feeds earth"
	)


func test_neutral_and_same() -> void:
	var rules := _rules()
	assert_almost_eq(rules.multiplier(ElementStats.METAL, ElementStats.EARTH), 1.0, "neutral")
	assert_almost_eq(rules.multiplier(ElementStats.FIRE, ElementStats.FIRE), 1.0, "same element")


func test_light_and_dark_mutual_counter() -> void:
	var rules := _rules()
	assert_almost_eq(rules.multiplier(ElementStats.LIGHT, ElementStats.DARK), 1.5, "light > dark")
	assert_almost_eq(rules.multiplier(ElementStats.DARK, ElementStats.LIGHT), 1.5, "dark > light")


func test_custom_element_is_easy_to_add() -> void:
	var defs := ElementDefaults.all()
	var custom := ElementDef.new()
	custom.id = &"custom_shadow"
	custom.tier = 3
	custom.overcomes.append(ElementStats.FIRE)
	defs.append(custom)
	var rules := ElementRules.new(defs)
	assert_eq(rules.overcomes(&"custom_shadow", ElementStats.FIRE), true, "custom overcomes")
	assert_almost_eq(
		rules.multiplier(&"custom_shadow", ElementStats.FIRE), 1.5, "custom element works"
	)


## ADR 0921: the tier-3 triad is a CLOSED cycle — void > chaos > time > void — and
## neutral against every tier-1/2 element. The closed cycle is what keeps a tier-3
## element from being a strict best response, and the neutral lower rows are what leave
## the measured ten-element table exactly where ADR 0069 pinned it.
func test_the_tier_three_triad_is_a_closed_cycle() -> void:
	var rules := _rules()
	assert_almost_eq(rules.multiplier(ElementStats.VOID, ElementStats.CHAOS), 1.5, "void > chaos")
	assert_almost_eq(rules.multiplier(ElementStats.CHAOS, ElementStats.VOID), 0.5, "chaos < void")
	assert_almost_eq(rules.multiplier(ElementStats.CHAOS, ElementStats.TIME), 1.5, "chaos > time")
	assert_almost_eq(rules.multiplier(ElementStats.TIME, ElementStats.CHAOS), 0.5, "time < chaos")
	assert_almost_eq(rules.multiplier(ElementStats.TIME, ElementStats.VOID), 1.5, "time > void")
	assert_almost_eq(rules.multiplier(ElementStats.VOID, ElementStats.TIME), 0.5, "void < time")
	for lower in ElementStats.BASE_ELEMENTS + ElementStats.ADVANCED_ELEMENTS:
		for triad in ElementStats.TIER_THREE_ELEMENTS:
			assert_almost_eq(
				rules.multiplier(triad, lower), 1.0, "%s is neutral against %s" % [triad, lower]
			)
			assert_almost_eq(
				rules.multiplier(lower, triad), 1.0, "%s is neutral against %s" % [lower, triad]
			)
