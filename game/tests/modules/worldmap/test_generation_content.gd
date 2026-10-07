extends TestCase

## THE CONTENT FAMILY: resources, structures, landmarks, encounters, NPCs.
##
## Every case generates through the standard pass set with real catalog art.
## Props from every writer coexist (the pipeline concatenates); blocking
## footprints from the new writers seal through the collision pass; data-only
## layers (encounters, NPCs) never render and never block.

const ENV := "mortal_greenwood"
const SIZE := 8
const SEED := 1234


func _config(overrides: Dictionary = {}) -> Dictionary:
	var config := {"environment": ENV, "scatter": []}
	for key in overrides.keys():
		config[key] = overrides[key]
	return config


func _chunk(config: Dictionary) -> WorldChunk:
	return WorldmapApi.default_generator().generate("node", 0, 0, SIZE, SEED, config)


func _have(archetype: String) -> bool:
	return not WorldmapAssets.by_archetype(ENV, archetype).is_empty()


func test_resources_place_yield_and_seal() -> void:
	var ore := "stone_and_ore.ore_vein"
	var herb := "flora.cultivation_herb"
	assert_eq(_have(ore), true, "the ore art exists")
	assert_eq(_have(herb), true, "and so does the herb")
	var chunk := _chunk(
		_config(
			{
				"resources":
				[
					{"archetype": ore, "density": 0.2, "blocking": true, "yield": {"ore": 2}},
					{"archetype": herb, "density": 0.2, "blocking": false, "yield": {"herb": 1}},
				]
			}
		)
	)
	var ores := 0
	var herbs := 0
	for prop in chunk.props:
		var row := prop as Dictionary
		if String(row.get("archetype", "")) == ore:
			ores += 1
			assert_eq(
				int((row.get("yield", {}) as Dictionary).get("ore", 0)),
				2,
				"veins carry their yield"
			)
			var base := row.get("cell", Vector2i(-1, -1)) as Vector2i
			assert_eq(chunk.standable(base.x, base.y), false, "and a blocking vein seals")
		if String(row.get("archetype", "")) == herb:
			herbs += 1
	assert_eq(ores > 0, true, "ore placed")
	assert_eq(herbs > 0, true, "herbs placed")


func test_scatter_and_resources_coexist() -> void:
	var chunk := _chunk(
		_config(
			{
				"scatter": [{"archetype": "flora.shrub", "density": 0.1, "blocking": true}],
				"resources":
				[
					{
						"archetype": "stone_and_ore.ore_vein",
						"density": 0.1,
						"blocking": true,
						"yield": {"ore": 1}
					}
				],
			}
		)
	)
	var shrubs := 0
	var ores := 0
	for prop in chunk.props:
		var arch := String((prop as Dictionary).get("archetype", ""))
		if arch == "flora.shrub":
			shrubs += 1
		if arch == "stone_and_ore.ore_vein":
			ores += 1
	assert_eq(
		shrubs > 0 and ores > 0,
		true,
		"no writer eats another (%d shrubs, %d veins)" % [shrubs, ores]
	)


func test_structures_keep_clearance_and_cap_counts() -> void:
	var hut := "settlement_and_domain_prop.shelter"
	assert_eq(_have(hut), true, "the shelter art exists")
	var chunk := _chunk(
		_config({"structures": [{"archetype": hut, "blocking": true}], "landmark_density": 0.0})
	)
	assert_eq((chunk.props as Array).size() <= 6, true, "at most six structures")
	var cells: Array = []
	for prop in chunk.props:
		var row := prop as Dictionary
		var base := row.get("cell", Vector2i(-1, -1)) as Vector2i
		var fp := row.get("footprint", Vector2i.ONE) as Vector2i
		assert_eq(
			base.x >= 0 and base.y >= 0 and base.x + fp.x <= SIZE and base.y + fp.y <= SIZE,
			true,
			"every structure fits the chunk"
		)
		for seen in cells:
			assert_eq(
				WorldmapPlacement.rects_overlap(
					base,
					fp,
					(seen as Dictionary).get("cell"),
					(seen as Dictionary).get("footprint"),
					1
				),
				false,
				"with clearance between structures"
			)
		cells.append({"cell": base, "footprint": fp})
		assert_eq(chunk.standable(base.x, base.y), false, "and a solid hut seals")


func test_a_settlement_lands_as_one_group() -> void:
	var hut := "settlement_and_domain_prop.shelter"
	var crate := "settlement_and_domain_prop.supply_crate"
	if not _have(hut) or not _have(crate):
		return
	var chunk := _chunk(
		_config(
			{
				"settlements":
				[
					{
						"count": 1,
						"spacing": 2,
						"plots":
						[
							{"archetype": hut, "dx": 0, "dy": 0},
							{"archetype": crate, "dx": 2, "dy": 0},
						],
					}
				]
			}
		)
	)
	var hamlet: Array = []
	for prop in chunk.props:
		if (prop as Dictionary).has("hamlet"):
			hamlet.append(prop)
	assert_eq(hamlet.size(), 2, "both plots of one hamlet stand or neither does")
	var a := (hamlet[0] as Dictionary).get("cell") as Vector2i
	var b := (hamlet[1] as Dictionary).get("cell") as Vector2i
	assert_eq(a - b, Vector2i(-2, 0), "at the authored offset")


func test_a_chunk_holds_at_most_one_landmark() -> void:
	var chunk := _chunk(_config({}))
	var layer := chunk.layers.get("landmark", {}) as Dictionary
	var marks := 0
	for prop in chunk.props:
		if String((prop as Dictionary).get("archetype", "")).begins_with(
			"landmark_and_environment_detail"
		):
			marks += 1
	assert_eq(marks <= 1, true, "at most one landmark prop")
	if layer.is_empty():
		assert_eq(marks, 0, "and the layer agrees when the roll refuses")
	else:
		assert_eq(marks, 1, "and the layer agrees when it places")
		assert_eq(
			String(layer.get("archetype", "")),
			String(
				(chunk.props as Array).reduce(
					func(found: String, prop: Dictionary) -> String:
						return (
							String(prop.get("archetype", ""))
							if String(prop.get("archetype", "")).begins_with(
								"landmark_and_environment_detail"
							)
							else found
						),
					""
				)
			),
			"naming the same archetype"
		)


func test_an_entrance_landmark_suggests_but_builds_no_edge() -> void:
	var mouth := "landmark_and_environment_detail.cave_entrance"
	if not _have(mouth):
		return
	var chunk := _chunk(_config({"landmarks": [mouth], "landmark_density": 1.0}))
	var layer := chunk.layers.get("landmark", {}) as Dictionary
	assert_eq(layer.is_empty(), false, "the mouth placed at density 1")
	assert_eq(bool(layer.get("suggests_edge", false)), true, "suggesting an edge")
	assert_eq((chunk.props as Array).size(), 1, "while building no edge and one prop")


func test_encounters_mark_ground_without_rendering() -> void:
	var before := _chunk(_config())
	var chunk := _chunk(
		_config(
			{
				"encounter_tables":
				[{"id": "beasts", "weight": 3.0}, {"id": "herbs", "weight": 1.0}],
				"encounter_density": 0.3,
			}
		)
	)
	var marks := chunk.layers.get("encounters", []) as Array
	assert_eq(marks.is_empty(), false, "markers placed")
	assert_eq(marks.size() <= 8, true, "capped per chunk")
	assert_eq(
		(chunk.props as Array).size(), (before.props as Array).size(), "while rendering nothing new"
	)
	for mark in marks:
		var row := mark as Dictionary
		var cell := Vector2i(
			int((row.get("cell", [0, 0]) as Array)[0]), int((row.get("cell", [0, 0]) as Array)[1])
		)
		assert_eq(chunk.standable(cell.x, cell.y), true, "on open ground")


func test_npc_markers_gather_at_structures_with_roles_in_order() -> void:
	var hut := "settlement_and_domain_prop.shelter"
	if not _have(hut):
		return
	var chunk := _chunk(
		_config(
			{
				"structures": [{"archetype": hut, "blocking": true}],
				"npc_roles": ["elder", "hunter"],
			}
		)
	)
	var marks := chunk.layers.get("npc_spawns", []) as Array
	assert_eq(marks.is_empty(), false, "structures draw markers")
	assert_eq(String((marks[0] as Dictionary).get("role", "")), "elder", "in role order")
	var lone := _chunk(_config({"npc_roles": ["hermit"]}))
	assert_eq(
		(lone.layers.get("npc_spawns", []) as Array).is_empty(),
		true,
		"while roles without structures mark nothing"
	)


func test_missing_art_places_nothing() -> void:
	var chunk := _chunk(
		_config(
			{
				"resources":
				[{"archetype": "stone_and_ore.no_such_vein", "density": 1.0, "blocking": true}],
				"structures": [{"archetype": "settlement_and_domain_prop.no_such_hut"}],
				"landmark_density": 0.0,
			}
		)
	)
	assert_eq((chunk.props as Array).is_empty(), true, "no art, no props, no holes")


func test_the_full_config_regenerates_deterministically() -> void:
	var config := _config(
		{
			"palette": ["ground_tile.base_ground", "ground_tile.soft_ground"],
			"roads": 1,
			"resources":
			[{"archetype": "flora.cultivation_herb", "density": 0.2, "blocking": false}],
			"structures": [{"archetype": "settlement_and_domain_prop.shelter"}],
			"landmark_density": 1.0,
			"encounter_tables": [{"id": "beasts", "weight": 1.0}],
			"encounter_density": 0.3,
			"npc_roles": ["elder"],
		}
	)
	var first := WorldmapApi.default_generator().generate("node", 0, 0, SIZE, SEED, config)
	var second := WorldmapApi.default_generator().generate("node", 0, 0, SIZE, SEED, config)
	assert_eq(
		JSON.stringify(first.to_dict()),
		JSON.stringify(second.to_dict()),
		"the whole content family regenerates byte-identically"
	)
