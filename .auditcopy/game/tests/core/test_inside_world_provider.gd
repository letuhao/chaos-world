extends TestCase

## ADR 0018: InsideWorldProvider tests.


func test_provider_returns_empty_without_world() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(InsideWorldProvider.new())
	assert_eq(actor.stats.derived(&"inside_world_size"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"inside_world_stability"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"inside_world_qi_density"), 0.0, "no world = 0")
	assert_eq(actor.stats.derived(&"inside_world_time_flow"), 0.0, "no world = 0")


func test_provider_contributes_stats() -> void:
	var actor := Actor.new(&"hero")
	var world := InsideWorld.new(InsideWorld.POCKET, 25.0, 0.7, 2.5, 4.0)
	actor.inside_world = world
	actor.set_component(&"inside_world", world)
	actor.stats.add_provider(InsideWorldProvider.new())
	assert_eq(actor.stats.derived(&"inside_world_size"), 25.0, "size contributed")
	assert_eq(actor.stats.derived(&"inside_world_stability"), 0.7, "stability contributed")
	assert_eq(actor.stats.derived(&"inside_world_qi_density"), 2.5, "qi_density contributed")
	assert_eq(actor.stats.derived(&"inside_world_time_flow"), 4.0, "time_flow contributed")


func test_provider_reflects_world_changes() -> void:
	var actor := Actor.new(&"hero")
	var world := InsideWorld.new()
	actor.inside_world = world
	actor.set_component(&"inside_world", world)
	actor.stats.add_provider(InsideWorldProvider.new())
	assert_eq(actor.stats.derived(&"inside_world_size"), 1.0, "initial size")
	world.expand_size(10.0)
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"inside_world_size"), 11.0, "size updated")
	world.improve_stability(0.3)
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"inside_world_stability"), 0.8, "stability updated")
