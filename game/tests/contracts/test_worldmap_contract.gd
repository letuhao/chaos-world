extends TestCase

## THE PASS CONTRACT: layers are named, requirements resolve, silence fails.
##
## Generation is `seed -> context -> passes -> chunk`, and passes are the only
## thing that can be added without touching the pipeline. These cases pin the
## three rules that keep that true: a pass without a layer name is refused, a
## requirement no pass provides fails the chunk loudly, and producers run
## before their readers.


func test_an_unnamed_pass_is_refused() -> void:
	var generator := WorldmapGenerator.new()
	var outcome := generator.register_pass(WorldmapContract.new())
	assert_eq(bool(outcome["ok"]), false, "a pass with no layer is refused")
	assert_eq(String(outcome["reason"]), "unnamed_pass", "and says so by name")


func test_a_duplicate_layer_is_refused() -> void:
	var generator := WorldmapGenerator.new()
	assert_eq(bool(generator.register_pass(WorldmapTerrainPass.new())["ok"]), true, "setup")
	var outcome := generator.register_pass(WorldmapTerrainPass.new())
	assert_eq(bool(outcome["ok"]), false, "two writers of one layer are refused")
	assert_eq(String(outcome["reason"]), "duplicate_layer", "and say so by name")


func test_readers_run_after_their_requirements() -> void:
	var generator := WorldmapGenerator.new()
	# Registered backwards on purpose: the pipeline orders, not the caller.
	generator.register_pass(WorldmapElevationPass.new())
	generator.register_pass(WorldmapTerrainPass.new())
	var chunk := generator.generate("node", 0, 0, 6, 7, _config())
	assert_eq(chunk.terrain.size(), 6, "terrain was laid")
	assert_eq((chunk.layers.get("elevation", []) as Array).size(), 6, "before elevation read it")


func test_the_standard_set_registers_every_layer() -> void:
	var generator := WorldmapApi.default_generator()
	var names: Array = []
	for layer in generator.layers():
		names.append(String(layer))
	names.sort()
	assert_eq(
		names,
		[
			"authored",
			"collision",
			"elevation",
			"encounters",
			"landmarks",
			"metadata",
			"navigation",
			"npc_spawns",
			"resources",
			"roads",
			"scatter",
			"structures",
			"terrain",
			"water",
		],
		"the standard set registers every layer"
	)
	var chunk := generator.generate("node", 0, 0, 6, 7, _config())
	assert_eq(chunk.terrain.size(), 6, "terrain was laid before water read it")
	assert_eq(chunk.walkable.size(), 6, "and collision ran last over everything")


func test_an_unsatisfiable_requirement_fails_loudly() -> void:
	var generator := WorldmapGenerator.new()
	# Collision without its producers: no terrain, no scatter, no chunk.
	generator.register_pass(WorldmapCollisionPass.new())
	var chunk := generator.generate("node", 0, 0, 6, 7, _config())
	assert_eq(chunk.walkable.is_empty(), true, "nothing is generated on missing input")


func _config() -> Dictionary:
	return {
		"environment": "mortal_greenwood",
		"scatter":
		[
			{"archetype": "flora.shrub", "density": 0.2, "blocking": true},
		],
	}
