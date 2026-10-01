extends TestCase

## ADR 0018: Inside World state tests.


func test_inside_world_creation_defaults() -> void:
	var world := InsideWorld.new()
	assert_eq(world.tier, InsideWorld.SEED, "default tier is seed")
	assert_eq(world.size, 1.0, "default size")
	assert_eq(world.stability, 0.5, "default stability")
	assert_eq(world.qi_density, 1.0, "default qi_density")
	assert_eq(world.time_flow, 1.0, "default time_flow")
	assert_eq(world.laws.is_empty(), true, "no laws by default")


func test_inside_world_creation_custom() -> void:
	var world := InsideWorld.new(InsideWorld.POCKET, 10.0, 0.8, 2.0, 3.0)
	assert_eq(world.tier, InsideWorld.POCKET, "custom tier")
	assert_eq(world.size, 10.0, "custom size")
	assert_eq(world.stability, 0.8, "custom stability")
	assert_eq(world.qi_density, 2.0, "custom qi_density")
	assert_eq(world.time_flow, 3.0, "custom time_flow")


func test_inside_world_is_stable() -> void:
	var world := InsideWorld.new()
	assert_eq(world.is_stable(), true, "0.5 is stable")
	world.stability = 0.4
	assert_eq(world.is_stable(), false, "below 0.5 is unstable")
	world.stability = 0.5
	assert_eq(world.is_stable(), true, "exactly 0.5 is stable")


func test_inside_world_expand_size() -> void:
	var world := InsideWorld.new()
	world.expand_size(5.0)
	assert_eq(world.size, 6.0, "size increased")
	world.expand_size(-3.0)
	assert_eq(world.size, 3.0, "size decreased")
	world.expand_size(-10.0)
	assert_eq(world.size, 0.0, "size clamped to 0")


func test_inside_world_improve_stability() -> void:
	var world := InsideWorld.new()
	world.improve_stability(0.3)
	assert_eq(world.stability, 0.8, "stability increased")
	world.improve_stability(0.5)
	assert_eq(world.stability, 1.0, "stability clamped to 1.0")
	world.improve_stability(-0.6)
	assert_eq(world.stability, 0.4, "stability decreased")
	world.improve_stability(-0.5)
	assert_eq(world.stability, 0.0, "stability clamped to 0.0")


func test_inside_world_laws() -> void:
	var world := InsideWorld.new()
	assert_eq(world.get_law(&"fire"), 0.0, "no law returns 0")
	world.add_law(&"fire", 0.7)
	assert_eq(world.get_law(&"fire"), 0.7, "law set")
	world.add_law(&"water", 0.3)
	assert_eq(world.get_law(&"water"), 0.3, "second law")
	world.add_law(&"fire", 0.9)
	assert_eq(world.get_law(&"fire"), 0.9, "law updated")


func test_inside_world_serialization() -> void:
	var world := InsideWorld.new(InsideWorld.INNER, 50.0, 0.9, 3.0, 5.0)
	world.add_law(&"fire", 0.8)
	world.add_law(&"earth", 0.6)
	var data := world.to_dict()
	assert_eq(data["tier"], "inner", "tier serialized")
	assert_eq(data["size"], 50.0, "size serialized")
	assert_eq(data["stability"], 0.9, "stability serialized")
	assert_eq(data["qi_density"], 3.0, "qi_density serialized")
	assert_eq(data["time_flow"], 5.0, "time_flow serialized")
	assert_eq(data["laws"]["fire"], 0.8, "fire law serialized")
	assert_eq(data["laws"]["earth"], 0.6, "earth law serialized")
	var restored := InsideWorld.from_dict(data)
	assert_eq(restored.tier, InsideWorld.INNER, "tier restored")
	assert_eq(restored.size, 50.0, "size restored")
	assert_eq(restored.stability, 0.9, "stability restored")
	assert_eq(restored.qi_density, 3.0, "qi_density restored")
	assert_eq(restored.time_flow, 5.0, "time_flow restored")
	assert_eq(restored.get_law(&"fire"), 0.8, "fire law restored")
	assert_eq(restored.get_law(&"earth"), 0.6, "earth law restored")


func test_inside_world_from_dict_defaults() -> void:
	var world := InsideWorld.from_dict({})
	assert_eq(world.tier, InsideWorld.SEED, "default tier")
	assert_eq(world.size, 1.0, "default size")
	assert_eq(world.stability, 0.5, "default stability")
	assert_eq(world.qi_density, 1.0, "default qi_density")
	assert_eq(world.time_flow, 1.0, "default time_flow")
	assert_eq(world.laws.is_empty(), true, "no laws")
