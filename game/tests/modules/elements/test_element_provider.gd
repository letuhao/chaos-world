extends TestCase

## ADR 0004/0002: the elements module contributes per-element derived stats.


func test_power_from_affinity() -> void:
	var actor := Actor.new(&"mage")
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)), 10.0, "fire power"
	)


func test_mastery_scales_power() -> void:
	var actor := Actor.new(&"mage", {ElementStats.mastery_id(ElementStats.FIRE): 5.0})
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)), 15.0, "scaled")


func test_resistance_from_affinity_and_will() -> void:
	var actor := Actor.new(&"mage", {Stat.WILL: 10.0})
	actor.set_affinity(ElementStats.WATER, 10.0)
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.resistance_id(ElementStats.WATER)), 7.0, "resistance"
	)
