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


class CountingProvider:
	extends StatProvider

	var calls: int = 0

	func contribute(_context: StatContext) -> Dictionary:
		calls += 1
		return {&"call_count": float(calls)}


func test_provider_contributes_stat() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 7.0})
	actor.stats.add_provider(DoublePhysiqueProvider.new())
	assert_almost_eq(actor.stats.derived(&"doubled_physique"), 14.0, "provider stat")


func test_provider_sees_live_resources() -> void:
	var actor := Actor.new(&"hero")
	actor.add_resource(ResourcePool.new(&"corruption", 100.0))
	actor.stats.add_provider(CorruptionReader.new())
	actor.change_resource(&"corruption", -40.0)
	assert_almost_eq(actor.stats.derived(&"corruption_ratio"), 0.6, "live resource")


func test_provider_sees_paths() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	actor.stats.add_provider(PathCountProvider.new())
	assert_almost_eq(actor.stats.derived(&"path_count"), 1.0, "provider sees paths")


func test_provider_cache_invalidates_on_change() -> void:
	var provider := CountingProvider.new()
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(provider)
	assert_almost_eq(actor.stats.derived(&"call_count"), 1.0, "first compute")
	assert_almost_eq(actor.stats.derived(&"call_count"), 1.0, "cached, not recomputed")
	actor.set_affinity(&"fire", 1.0)
	assert_almost_eq(actor.stats.derived(&"call_count"), 2.0, "recomputed after change")
