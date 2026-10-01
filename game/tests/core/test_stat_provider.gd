extends TestCase

## ADR 0002: modules contribute derived stats through a StatProvider.


class DoublePhysiqueProvider:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		return {&"doubled_physique": context.base_value(Stat.PHYSIQUE) * 2.0}


class CorruptionReader:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		var pool := context.resource(&"corruption")
		var ratio := 0.0 if pool == null else pool.current / pool.maximum
		return {&"corruption_ratio": ratio}


class PathCountProvider:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		return {&"path_count": float(context.paths.size())}


func test_provider_contributes_stat() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 7.0})
	actor.stats.add_provider(DoublePhysiqueProvider.new())
	assert_almost_eq(actor.stats.derived(&"doubled_physique"), 14.0, "provider stat")


func test_provider_sees_live_resources() -> void:
	var actor := Actor.new(&"hero")
	actor.add_resource(ResourcePool.new(&"corruption", 100.0))
	actor.stats.add_provider(CorruptionReader.new())
	actor.resource(&"corruption").change(-40.0)
	assert_almost_eq(actor.stats.derived(&"corruption_ratio"), 0.6, "live resource")


func test_provider_sees_paths() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	actor.stats.add_provider(PathCountProvider.new())
	assert_almost_eq(actor.stats.derived(&"path_count"), 1.0, "provider sees paths")
