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
	var void_def := ElementDef.new()
	void_def.id = &"void"
	void_def.tier = 3
	void_def.overcomes.append(ElementStats.FIRE)
	defs.append(void_def)
	var rules := ElementRules.new(defs)
	assert_eq(rules.overcomes(&"void", ElementStats.FIRE), true, "custom overcomes")
	assert_almost_eq(rules.multiplier(&"void", ElementStats.FIRE), 1.5, "custom element works")
