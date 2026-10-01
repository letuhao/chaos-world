extends TestCase

## ADR 0020: TribulationCondition tests.


func test_tribulation_condition_describe() -> void:
	var condition := TribulationCondition.new()
	assert_eq(condition.describe(), "tribulation required", "describe returns tribulation required")


func test_tribulation_condition_allows_low_realm() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	var condition := TribulationCondition.new()
	# Mortal realm (index 0) — no tribulation needed
	assert_eq(
		condition.can_breakthrough(actor, actor.path(&"qi"), {}), true, "mortal realm allowed"
	)


func test_tribulation_condition_blocks_without_preparation() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"earth_immortal"))
	var condition := TribulationCondition.new()
	# Immortal realm (index 18) — tribulation required but not prepared
	assert_eq(
		condition.can_breakthrough(actor, actor.path(&"qi"), {}),
		false,
		"immortal realm blocked without preparation"
	)


func test_tribulation_condition_allows_with_preparation() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"earth_immortal"))
	var tribulation := Tribulation.new(Tribulation.LIGHTNING, 3, 1.0)
	tribulation.preparation = {"formation": 0.3}
	actor.tribulation = tribulation
	var condition := TribulationCondition.new()
	assert_eq(
		condition.can_breakthrough(actor, actor.path(&"qi"), {}),
		true,
		"immortal realm allowed with preparation"
	)


func test_tribulation_condition_spirit_realm_allowed() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"spirit_ascension"))
	var condition := TribulationCondition.new()
	# Spirit realm (index 17) — no tribulation needed
	assert_eq(
		condition.can_breakthrough(actor, actor.path(&"qi"), {}), true, "spirit realm allowed"
	)
