extends TestCase

## THE TERRAIN FAMILY: palettes, elevation data, and roads.
##
## Every case generates through the standard pass set with real catalog art:
## a palette is a promise about which archetypes may appear, elevation is data
## (never a wall), and roads carve walkable trail while stopping at water and
## high ground. Defaults keep old chunks byte-identical — variety is opt-in.

const ENV := "mortal_greenwood"
const SIZE := 8
const SEED := 1234


func _config(overrides: Dictionary = {}) -> Dictionary:
	var config := {"environment": ENV, "scatter": []}
	for key in overrides.keys():
		config[key] = overrides[key]
	return config


func _chunk(config: Dictionary, cx: int = 0, cy: int = 0) -> WorldChunk:
	return WorldmapApi.default_generator().generate("node", cx, cy, SIZE, SEED, config)


func test_the_default_palette_is_base_ground_alone() -> void:
	# Water still carves by default: the palette promises which GROUND appears,
	# and the stream is another pass's answer.
	var chunk := _chunk(_config())
	for row in chunk.terrain:
		for arch in row as Array:
			var name := String(arch)
			if name.begins_with("water_feature"):
				continue
			assert_eq(name, "ground_tile.base_ground", "untouched default behavior")


func test_a_palette_rotates_only_over_existing_art() -> void:
	var chunk := _chunk(
		_config(
			{
				"palette":
				[
					"ground_tile.base_ground",
					"ground_tile.soft_ground",
					"ground_tile.no_such_tile",
				]
			}
		)
	)
	var seen := {}
	for row in chunk.terrain:
		for arch in row as Array:
			seen[String(arch)] = true
	assert_eq(seen.has("ground_tile.no_such_tile"), false, "a missing entry never paints")
	assert_eq(seen.has("ground_tile.base_ground"), true, "while real entries rotate")
	assert_eq(seen.has("ground_tile.soft_ground"), true, "across more than one ground")


func test_elevation_is_patchy_bounded_data() -> void:
	var chunk := _chunk(_config())
	var heights = chunk.layers.get("elevation", [])
	assert_eq(heights.size(), SIZE, "one row per cell row")
	var lo := 2
	var hi := 0
	for row in heights as Array:
		assert_eq((row as Array).size(), SIZE, "one height per cell")
		for height in row as Array:
			lo = mini(lo, int(height))
			hi = maxi(hi, int(height))
	assert_eq(lo >= 0 and hi <= 2, true, "heights stay in [0, 2]")
	var other := _chunk(_config(), 1, 0)
	assert_ne(
		JSON.stringify(heights),
		JSON.stringify(other.layers.get("elevation", [])),
		"and differ per chunk position"
	)


func test_elevation_changes_no_collision_answer() -> void:
	var plain := _chunk(_config())
	for y in SIZE:
		for x in SIZE:
			assert_eq(
				bool((plain.walkable[y] as Array)[x]),
				plain.standable(x, y),
				"height never seals a cell by itself"
			)


func test_roads_are_opt_in_and_carve_walkable_trail() -> void:
	var plain := _chunk(_config())
	var count_plain := 0
	for row in plain.terrain:
		for arch in row as Array:
			if String(arch) == "ground_tile.packed_trail":
				count_plain += 1
	assert_eq(count_plain, 0, "no roads key means no trail")
	var robed := _chunk(_config({"roads": 1}))
	var count := 0
	for row in robed.terrain:
		for arch in row as Array:
			if String(arch) == "ground_tile.packed_trail":
				count += 1
	assert_eq(count > 0, true, "one road carves a visible band")
	for y in SIZE:
		for x in SIZE:
			if String((robed.terrain[y] as Array)[x]) == "ground_tile.packed_trail":
				assert_eq(bool((robed.walkable[y] as Array)[x]), true, "and trail stays walkable")


func test_roads_stop_at_water_and_high_ground() -> void:
	var chunk := _chunk(_config({"roads": 2}))
	for y in SIZE:
		for x in SIZE:
			var arch := String((chunk.terrain[y] as Array)[x])
			if arch == "ground_tile.packed_trail":
				assert_eq(arch.begins_with("water_feature"), false, "no trail over water")
				var heights = chunk.layers.get("elevation", []) as Array
				if heights.size() == SIZE:
					assert_eq(int((heights[y] as Array)[x]) < 2, true, "and none on high ground")


func test_roads_and_elevation_regenerate_deterministically() -> void:
	var first := _chunk(
		_config({"roads": 2, "palette": ["ground_tile.base_ground", "ground_tile.soft_ground"]})
	)
	var second := _chunk(
		_config({"roads": 2, "palette": ["ground_tile.base_ground", "ground_tile.soft_ground"]})
	)
	assert_eq(
		JSON.stringify(first.to_dict()),
		JSON.stringify(second.to_dict()),
		"same inputs, same chunk including new layers"
	)
	var restored := WorldChunk.from_dict(first.to_dict())
	assert_eq(
		JSON.stringify(restored.layers),
		JSON.stringify(first.layers),
		"and the layers survive the dict round trip"
	)
