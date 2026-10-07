extends TestCase

## THE SYSTEMS: navigation regions, the metadata summary, and templates.
##
## Regions label the generated ground (exact answers stay with `standable`);
## metadata indexes everything the chunk holds at one address; templates turn
## generation config into validated, reusable data. All three read the real
## pipeline with real catalog art.

const ENV := "mortal_greenwood"
const SIZE := 8
const SEED := 1234


func setup() -> void:
	WorldmapTemplates.clear()


func teardown() -> void:
	WorldmapTemplates.clear()


func _config(overrides: Dictionary = {}) -> Dictionary:
	var config := {"environment": ENV, "scatter": []}
	for key in overrides.keys():
		config[key] = overrides[key]
	return config


func _chunk(config: Dictionary) -> WorldChunk:
	return WorldmapApi.default_generator().generate("node", 0, 0, SIZE, SEED, config)


func test_regions_cover_exactly_the_walkable_ground() -> void:
	var chunk := _chunk(_config())
	var nav := chunk.layers.get("navigation", {}) as Dictionary
	assert_eq(nav.is_empty(), false, "navigation labeled the chunk")
	var regions := nav.get("regions", []) as Array
	var open := 0
	for y in SIZE:
		for x in SIZE:
			var id := int((regions[y] as Array)[x])
			if bool((chunk.walkable[y] as Array)[x]):
				open += 1
				assert_eq(id >= 0, true, "every walkable cell has a region")
			else:
				assert_eq(id, -1, "and no blocked cell does")
	var total := 0
	for id in (nav.get("sizes", {}) as Dictionary).keys():
		total += int((nav.get("sizes", {}) as Dictionary).get(id))
	assert_eq(total, open, "with sizes summing to the walkable count")
	assert_eq(int(nav.get("count", 0)) >= 1, true, "and at least one region")
	assert_eq(
		int((nav.get("sizes", {}) as Dictionary).get(int(nav.get("largest", -2)), -1)) > 0,
		true,
		"whose largest is a real region"
	)


func test_metadata_indexes_what_the_chunk_holds() -> void:
	var chunk := _chunk(
		_config(
			{
				"structures": [{"archetype": "settlement_and_domain_prop.shelter"}],
				"landmark_density": 1.0,
				"encounter_tables": [{"id": "beasts", "weight": 1.0}],
				"encounter_density": 0.3,
				"npc_roles": ["elder"],
			}
		)
	)
	var meta := chunk.layers.get("metadata", {}) as Dictionary
	assert_eq(meta.is_empty(), false, "metadata summarized the chunk")
	assert_eq(String(meta.get("chunk", "")), "node:0,0", "naming the chunk")
	assert_eq(String(meta.get("environment", "")), ENV, "and its environment")
	assert_eq(
		int(meta.get("walkable_cells", -1)) + int(meta.get("blocked_cells", -1)),
		SIZE * SIZE,
		"with cells that add up"
	)
	var kinds := {}
	for poi in meta.get("pois", []) as Array:
		kinds[String((poi as Dictionary).get("kind", ""))] = true
		var cell := (poi as Dictionary).get("cell", []) as Array
		assert_eq(cell.size(), 2, "every POI carries a cell")
	for kind in ["landmark", "encounter", "npc", "structure"]:
		assert_eq(kinds.has(kind), true, "indexing %ss" % kind)


func test_metadata_matches_the_layers_it_indexes() -> void:
	var chunk := _chunk(_config({"landmark_density": 1.0}))
	var meta := chunk.layers.get("metadata", {}) as Dictionary
	var landmark := chunk.layers.get("landmark", {}) as Dictionary
	var count := 0
	for poi in meta.get("pois", []) as Array:
		if String((poi as Dictionary).get("kind", "")) == "landmark":
			count += 1
			assert_eq(
				String((poi as Dictionary).get("archetype", "")),
				String(landmark.get("archetype", "")),
				"naming the same landmark the layer holds"
			)
	assert_eq(count, 1 if not landmark.is_empty() else 0, "exactly once")


func test_templates_register_validate_and_expand() -> void:
	assert_eq(
		String(WorldmapTemplates.register("potion", "x", {}).get("reason", "")),
		"unknown_kind",
		"an unknown kind is refused"
	)
	assert_eq(
		String(WorldmapTemplates.register("biome", "", {}).get("reason", "")),
		"empty_name",
		"as is an empty name"
	)
	assert_eq(
		String(WorldmapTemplates.register("biome", "bad", {}).get("reason", "")),
		"empty_environment",
		"and a biome without an environment"
	)
	assert_eq(
		String(
			WorldmapTemplates.register("settlement", "empty", {"plots": []}).get("reason", ""),
		),
		"empty_plots",
		"and a settlement without plots"
	)
	var outcome := WorldmapTemplates.register(
		"chunk", "glade", {"chunk_size": 8, "biome": "greenwood_wilderness", "roads": 1}
	)
	assert_eq(bool(outcome.get("ok", false)), true, "a well-formed chunk template registers")
	assert_eq(
		String(WorldmapTemplates.register("chunk", "glade", {}).get("reason", "")),
		"duplicate_template",
		"but never twice"
	)
	var config := WorldmapTemplates.chunk_config("glade", {"roads": 2})
	assert_eq(String(config.get("environment", "")), ENV, "the biome fragment flows in")
	assert_eq(int(config.get("chunk_size", 0)), 8, "with the template's own keys")
	assert_eq(int(config.get("roads", 0)), 2, "and overrides win")
	assert_eq(
		WorldmapTemplates.chunk_config("no_such_template").is_empty(),
		true,
		"while unknown answers {}"
	)
	var chunk := WorldmapApi.default_generator().generate("node", 0, 0, 8, SEED, config)
	assert_eq(chunk.terrain.size(), 8, "and the expansion generates")


func test_the_builtin_biome_is_real_and_clear_reseeds() -> void:
	assert_eq(WorldmapTemplates.names("biome"), ["greenwood_wilderness"], "one seeded biome")
	var body := WorldmapTemplates.get_template("biome", "greenwood_wilderness")
	assert_eq(String(body.get("environment", "")), ENV, "on real art")
	WorldmapTemplates.clear()
	assert_eq(
		WorldmapTemplates.names("biome"), ["greenwood_wilderness"], "clearing re-seeds on next read"
	)


func test_region_templates_validate_shape() -> void:
	assert_eq(
		String(
			(
				WorldmapTemplates
				. register(
					"region", "plaza", {"chunk_template": "glade", "coords": [[0, 0], [1, 0]]}
				)
				. get("reason", "")
			)
		),
		"",
		"a region with a template and coords registers"
	)
	assert_eq(
		String(
			WorldmapTemplates.register("region", "nowhere", {"coords": [[0, 0]]}).get("reason", "")
		),
		"empty_chunk_template",
		"while one without a chunk template refuses"
	)
	assert_eq(
		String(
			WorldmapTemplates.register("region", "flat", {"chunk_template": "glade"}).get(
				"reason", ""
			)
		),
		"empty_coords",
		"and one without coords refuses"
	)
