extends TestCase

## ADR 0019: WorldCreationProvider tests.


func test_provider_returns_empty_without_world() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(WorldCreationProvider.new())
	assert_eq(actor.stats.derived(&"world_size"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"world_stability"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"world_will"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"world_tier"), 0.0, "no world = 0")


func test_provider_contributes_stats() -> void:
	var actor := Actor.new(&"hero")
	var world := WorldState.new(WorldState.SMALL, 50.0, 0.8)
	world.will_strength = 0.6
	actor.world = world
	actor.set_component(&"world", world)
	actor.stats.add_provider(WorldCreationProvider.new())
	assert_eq(actor.stats.derived(&"world_size"), 50.0, "size contributed")
	assert_eq(actor.stats.derived(&"world_stability"), 0.8, "stability contributed")
	assert_eq(actor.stats.derived(&"world_will"), 0.6, "will contributed")
	assert_eq(actor.stats.derived(&"world_tier"), 1.0, "tier contributed (small=1)")


func test_provider_tier_mapping() -> void:
	var actor := Actor.new(&"hero")
	var world := WorldState.new(WorldState.MICRO, 1.0, 0.5)
	actor.world = world
	actor.set_component(&"world", world)
	actor.stats.add_provider(WorldCreationProvider.new())
	assert_eq(actor.stats.derived(&"world_tier"), 0.0, "micro = 0")
	world.tier = WorldState.GREAT
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"world_tier"), 2.0, "great = 2")


func test_provider_reflects_world_changes() -> void:
	var actor := Actor.new(&"hero")
	var world := WorldState.new()
	actor.world = world
	actor.set_component(&"world", world)
	actor.stats.add_provider(WorldCreationProvider.new())
	assert_eq(actor.stats.derived(&"world_size"), 1.0, "initial size")
	world.size = 25.0
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"world_size"), 25.0, "size updated")
	world.stability = 0.9
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"world_stability"), 0.9, "stability updated")
