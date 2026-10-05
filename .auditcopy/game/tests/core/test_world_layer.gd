extends TestCase

## ADR 0019: WorldLayerState tests.


func test_world_layer_creation_defaults() -> void:
	var layer := WorldLayerState.new()
	assert_eq(layer.layer_id, &"", "default layer_id is empty")
	assert_eq(layer.name, "", "default name is empty")
	assert_eq(layer.size_ratio, 1.0, "default size_ratio is 1.0")
	assert_eq(layer.laws.is_empty(), true, "no laws by default")


func test_world_layer_creation_custom() -> void:
	var layer := WorldLayerState.new(&"surface", "Surface", 0.5)
	assert_eq(layer.layer_id, &"surface", "custom layer_id")
	assert_eq(layer.name, "Surface", "custom name")
	assert_eq(layer.size_ratio, 0.5, "custom size_ratio")


func test_world_layer_serialization() -> void:
	var layer := WorldLayerState.new(&"heaven", "Heaven", 0.3)
	layer.laws.append(&"wind")
	layer.laws.append(&"lightning")
	var data := layer.to_dict()
	assert_eq(data["layer_id"], "heaven", "layer_id serialized")
	assert_eq(data["name"], "Heaven", "name serialized")
	assert_eq(data["size_ratio"], 0.3, "size_ratio serialized")
	assert_eq(data["laws"], ["wind", "lightning"], "laws serialized")
	var restored := WorldLayerState.from_dict(data)
	assert_eq(restored.layer_id, &"heaven", "layer_id restored")
	assert_eq(restored.name, "Heaven", "name restored")
	assert_eq(restored.size_ratio, 0.3, "size_ratio restored")
	assert_eq(restored.laws.size(), 2, "laws count restored")
	assert_eq(restored.laws[0], &"wind", "first law restored")
	assert_eq(restored.laws[1], &"lightning", "second law restored")


func test_world_layer_from_dict_defaults() -> void:
	var layer := WorldLayerState.from_dict({})
	assert_eq(layer.layer_id, &"", "default layer_id")
	assert_eq(layer.name, "", "default name")
	assert_eq(layer.size_ratio, 1.0, "default size_ratio")
	assert_eq(layer.laws.is_empty(), true, "no laws")
