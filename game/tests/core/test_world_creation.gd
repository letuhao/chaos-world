extends TestCase

## ADR 0019: WorldState tests.


func test_world_creation_defaults() -> void:
	var world := WorldState.new()
	assert_eq(world.tier, WorldState.MICRO, "default tier is micro")
	assert_eq(world.size, 1.0, "default size")
	assert_eq(world.stability, 0.5, "default stability")
	assert_eq(world.will_strength, 0.5, "default will_strength")
	assert_eq(world.laws.is_empty(), true, "no laws by default")
	assert_eq(world.layers.is_empty(), true, "no layers by default")
	assert_eq(world.inhabitants.is_empty(), true, "no inhabitants by default")
	assert_eq(world.resources.is_empty(), true, "no resources by default")
	assert_eq(world.upkeep_rate, 0.0, "default upkeep_rate")
	assert_eq(world.time_flow_rate, 1.0, "default time_flow_rate")


func test_world_creation_custom() -> void:
	var world := WorldState.new(WorldState.SMALL, 50.0, 0.8)
	assert_eq(world.tier, WorldState.SMALL, "custom tier")
	assert_eq(world.size, 50.0, "custom size")
	assert_eq(world.stability, 0.8, "custom stability")


func test_world_is_stable() -> void:
	var world := WorldState.new()
	assert_eq(world.is_stable(), true, "0.5 is stable")
	world.stability = 0.3
	assert_eq(world.is_stable(), true, "exactly 0.3 is stable")
	world.stability = 0.29
	assert_eq(world.is_stable(), false, "below 0.3 is unstable")
	world.stability = 0.0
	assert_eq(world.is_stable(), false, "0 is unstable")


func test_world_add_and_get_law() -> void:
	var world := WorldState.new()
	var law := WorldLawState.new(&"gravity", WorldLawState.PHYSICAL, 2.0)
	world.add_law(law)
	assert_eq(world.laws.size(), 1, "law added")
	var retrieved := world.get_law(&"gravity")
	assert_eq(retrieved != null, true, "law found")
	assert_eq(retrieved.value, 2.0, "law value correct")
	assert_eq(world.get_law(&"nonexistent") == null, true, "missing law returns null")


func test_world_add_layer() -> void:
	var world := WorldState.new()
	var layer := WorldLayerState.new(&"surface", "Surface", 1.0)
	world.add_layer(layer)
	assert_eq(world.layers.size(), 1, "layer added")
	assert_eq(world.layers[0].layer_id, &"surface", "layer_id correct")


func test_world_add_inhabitant() -> void:
	var world := WorldState.new()
	var inhabitant := InhabitantRef.new(&"spirit_beast", InhabitantRef.BEAST, 5, 0.7)
	world.add_inhabitant(inhabitant)
	assert_eq(world.inhabitants.size(), 1, "inhabitant added")
	assert_eq(world.inhabitants[0].count, 5, "count correct")
	assert_eq(world.inhabitants[0].loyalty, 0.7, "loyalty correct")


func test_world_pay_upkeep() -> void:
	var world := WorldState.new()
	world.upkeep_rate = 10.0
	assert_eq(world.pay_upkeep(15.0), true, "sufficient qi")
	assert_eq(world.pay_upkeep(5.0), false, "insufficient qi")
	assert_eq(world.pay_upkeep(10.0), true, "exact qi")


func test_world_serialization() -> void:
	var world := WorldState.new(WorldState.GREAT, 100.0, 0.9)
	world.will_strength = 0.8
	world.upkeep_rate = 5.0
	world.time_flow_rate = 10.0
	world.add_law(WorldLawState.new(&"fire", WorldLawState.ELEMENTAL, 0.7))
	world.add_layer(WorldLayerState.new(&"surface", "Surface", 0.6))
	world.add_inhabitant(InhabitantRef.new(&"human", InhabitantRef.HUMANOID, 100, 0.9))
	world.resources[&"herbs"] = 50.0
	var data := world.to_dict()
	assert_eq(data["tier"], "great", "tier serialized")
	assert_eq(data["size"], 100.0, "size serialized")
	assert_eq(data["stability"], 0.9, "stability serialized")
	assert_eq(data["will_strength"], 0.8, "will_strength serialized")
	assert_eq(data["upkeep_rate"], 5.0, "upkeep_rate serialized")
	assert_eq(data["time_flow_rate"], 10.0, "time_flow_rate serialized")
	assert_eq(data["laws"].size(), 1, "laws serialized")
	assert_eq(data["layers"].size(), 1, "layers serialized")
	assert_eq(data["inhabitants"].size(), 1, "inhabitants serialized")
	assert_eq(data["resources"]["herbs"], 50.0, "resources serialized")
	var restored := WorldState.from_dict(data)
	assert_eq(restored.tier, WorldState.GREAT, "tier restored")
	assert_eq(restored.size, 100.0, "size restored")
	assert_eq(restored.stability, 0.9, "stability restored")
	assert_eq(restored.will_strength, 0.8, "will_strength restored")
	assert_eq(restored.upkeep_rate, 5.0, "upkeep_rate restored")
	assert_eq(restored.time_flow_rate, 10.0, "time_flow_rate restored")
	assert_eq(restored.laws.size(), 1, "laws restored")
	assert_eq(restored.laws[0].law_id, &"fire", "law_id restored")
	assert_eq(restored.layers.size(), 1, "layers restored")
	assert_eq(restored.layers[0].layer_id, &"surface", "layer_id restored")
	assert_eq(restored.inhabitants.size(), 1, "inhabitants restored")
	assert_eq(restored.inhabitants[0].inhabitant_id, &"human", "inhabitant_id restored")
	assert_eq(restored.resources[&"herbs"], 50.0, "resources restored")


func test_world_from_dict_defaults() -> void:
	var world := WorldState.from_dict({})
	assert_eq(world.tier, WorldState.MICRO, "default tier")
	assert_eq(world.size, 1.0, "default size")
	assert_eq(world.stability, 0.5, "default stability")
	assert_eq(world.will_strength, 0.5, "default will_strength")
	assert_eq(world.laws.is_empty(), true, "no laws")
	assert_eq(world.layers.is_empty(), true, "no layers")
	assert_eq(world.inhabitants.is_empty(), true, "no inhabitants")
	assert_eq(world.upkeep_rate, 0.0, "default upkeep_rate")
	assert_eq(world.time_flow_rate, 1.0, "default time_flow_rate")
