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


class AffinityReader:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		return {&"fire_affinity": context.affinity(&"fire")}


class TraitReader:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		return {&"is_succubus": 1.0 if context.has_trait(&"succubus") else 0.0}


class PathProgressReader:
	extends StatProvider

	func contribute(context: StatContext) -> Dictionary:
		var state := context.path(&"qi")
		return {&"qi_progress": 0.0 if state == null else state.progress}


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


func test_direct_pool_mutation_invalidates() -> void:
	var actor := Actor.new(&"hero")
	actor.add_resource(ResourcePool.new(&"corruption", 100.0))
	actor.stats.add_provider(CorruptionReader.new())
	assert_almost_eq(actor.stats.derived(&"corruption_ratio"), 1.0, "full")
	actor.resource(&"corruption").change(-40.0)
	assert_almost_eq(actor.stats.derived(&"corruption_ratio"), 0.6, "pool signal invalidates")


func test_direct_affinity_mutation_invalidates() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(AffinityReader.new())
	assert_almost_eq(actor.stats.derived(&"fire_affinity"), 0.0, "none")
	actor.affinities.set_value(&"fire", 7.0)
	assert_almost_eq(actor.stats.derived(&"fire_affinity"), 7.0, "affinity signal invalidates")


func test_direct_trait_mutation_invalidates() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(TraitReader.new())
	assert_almost_eq(actor.stats.derived(&"is_succubus"), 0.0, "no trait")
	actor.traits.add(&"succubus")
	assert_almost_eq(actor.stats.derived(&"is_succubus"), 1.0, "trait signal invalidates")


func test_direct_path_mutation_invalidates() -> void:
	var actor := Actor.new(&"hero")
	var state := PathState.new(&"qi", &"qi_refining")
	actor.set_path(state)
	actor.stats.add_provider(PathProgressReader.new())
	assert_almost_eq(actor.stats.derived(&"qi_progress"), 0.0, "no progress")
	state.progress = 3.0
	assert_almost_eq(actor.stats.derived(&"qi_progress"), 3.0, "path signal invalidates")
