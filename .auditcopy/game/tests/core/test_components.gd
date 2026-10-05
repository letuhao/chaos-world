extends TestCase

## ADR 0007: Actor.components is a generic module extension point.


class ComponentReader:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		var marker := context.component(&"marker")
		return {&"has_marker": 1.0 if marker != null else 0.0}


func test_set_and_get_component() -> void:
	var actor := Actor.new(&"hero")
	var marker := ResourcePool.new(&"marker", 1.0)
	actor.set_component(&"marker", marker)
	assert_eq(actor.component(&"marker"), marker, "component stored")
	assert_eq(actor.component(&"missing"), null, "missing component")


func test_provider_sees_components() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(ComponentReader.new())
	assert_almost_eq(actor.stats.derived(&"has_marker"), 0.0, "none")
	actor.set_component(&"marker", ResourcePool.new(&"marker", 1.0))
	assert_almost_eq(actor.stats.derived(&"has_marker"), 1.0, "sees component")
