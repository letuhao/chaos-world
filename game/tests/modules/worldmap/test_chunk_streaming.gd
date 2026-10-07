extends TestCase

## THE VERTICAL SLICE: generated chunks stream, portals cross worlds, and
## nothing forgets. One scene, real catalog art, headless: generate a node,
## walk across a chunk seam, destroy ground, unload it, come back, and prove
## the hole is still there. Then take a portal to a smaller-chunked universe
## and a doorway into an authored cave, and merge four chunks into one region.
##
## Textures load for real (`load()` on catalog paths), so a missing asset is
## a failed test rather than an invisible sprite.

const ENV := "mortal_greenwood"
const SIZE := 8
const SEED := 1234

## Visit cap for test routes: the world past the cached chunks generates on
## demand, so an unbounded flood would walk an infinite wilderness forever.
const ROUTE_VISIT_CAP := 1024

var _graph: WorldmapGraph
var _configs: Dictionary
var _scene: WorldmapScene


func setup() -> void:
	WorldmapApi.clear_graph()
	_graph = WorldmapGraph.new()
	_graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	_graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	_graph.add_node({"id": "far", "kind": &"universe", "parent": ""})
	_configs = {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": SIZE,
			"seed": SEED,
			"entry_row": 1,
			"data_radius": 2,
			"scene_radius": 1,
			"scatter":
			[
				{"archetype": "flora.shrub", "density": 0.05, "blocking": true},
				{"archetype": "flora.flower_cluster", "density": 0.08, "blocking": false},
			],
		},
		"cave":
		{
			"environment": ENV,
			"chunk_size": 6,
			"seed": 99,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"water": false,
			"authored_terrain": _flat_ground(6),
			"scatter":
			[
				{"archetype": "stone_and_ore.small_rock", "density": 0.3, "blocking": true},
			],
		},
		"far":
		{
			"environment": ENV,
			"chunk_size": 12,
			"seed": 7,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter": [],
		},
	}
	_scene = null


func teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		if _scene.get_parent() != null:
			_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null
	WorldmapApi.clear_graph()


func _flat_ground(size: int) -> Array:
	var rows: Array = []
	for _y in size:
		var row: Array = []
		for _x in size:
			row.append("ground_tile.base_ground")
		rows.append(row)
	return rows


func _open() -> void:
	_scene = WorldmapScene.new()
	var outcome := _scene.open(_graph, "overworld", _configs)
	assert_eq(bool(outcome.get("ok", false)), true, "the node opens")


## A route from `from` to `to` over standable cells (bounded by
## `ROUTE_VISIT_CAP` above). Empty also means "unreachable" — the caller
## asserts reachability first so the two never blur.
func _route(from: Vector2i, to: Vector2i) -> Array:
	var prev := {from: -1}
	var queue: Array = [from]
	while not queue.is_empty() and prev.size() < ROUTE_VISIT_CAP:
		var current := queue.pop_front() as Vector2i
		if current == to:
			break
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + delta
			if prev.has(next):
				continue
			if not _scene.is_standable(next):
				continue
			prev[next] = current
			queue.append(next)
	if not prev.has(to):
		return []
	var route: Array = [to]
	var cursor: Vector2i = to
	while cursor != from:
		cursor = prev[cursor] as Vector2i
		route.push_front(cursor)
	return route


func _walk(route: Array) -> void:
	for i in range(1, route.size()):
		var step: Vector2i = (route[i] as Vector2i) - (route[i - 1] as Vector2i)
		var outcome := _scene.step(step.x, step.y)
		assert_eq(bool(outcome.get("moved", false)), true, "every routed step moves")


func _first_walkable() -> Vector2i:
	var streamer := _scene.streamer()
	for y in SIZE:
		for x in SIZE:
			var chunk := streamer.chunk_data("overworld", 0, 0, SIZE, SEED)
			if chunk.standable(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- Streaming ----------------------------------------------------------------


func test_opening_renders_the_scene_range_and_the_player_stands() -> void:
	_open()
	var view := _scene.debug_summary()
	assert_eq(String(view.get("node", "")), "overworld", "on the right node")
	assert_eq((view.get("holders", []) as Array).size(), 9, "3x3 holders at scene radius 1")
	var cell: Vector2i = Vector2i(view["player_cell"][0], view["player_cell"][1])
	assert_eq(_scene.is_standable(cell), true, "and the entry cell is standable")


func test_walking_crosses_a_chunk_seam_without_teleporting() -> void:
	_open()
	# The target must be walkable ground, not a water cell: picking a fixed
	# coordinate sent the route at a stream, which correctly found nothing.
	var target := _walkable_in_chunk(1, 0)
	assert_ne(target, Vector2i(-1, -1), "the next chunk has walkable ground")
	var route := _route(_scene.player_cell(), target)
	assert_eq(route.is_empty(), false, "a route exists across the seam")
	_walk(route)
	assert_eq(_scene.player_cell(), target, "and the player arrives cell by cell")
	var holders := _scene.debug_summary().get("holders", []) as Array
	assert_eq(holders.has("overworld:1,0"), true, "the new chunk rendered")
	assert_eq(holders.has("overworld:0,0"), true, "while the old one is still held")


## The first walkable cell of a chunk, or (-1, -1) when the chunk is all wall.
func _walkable_in_chunk(cx: int, cy: int) -> Vector2i:
	var chunk := _scene.streamer().chunk_data("overworld", cx, cy, SIZE, SEED)
	for y in SIZE:
		for x in SIZE:
			if chunk.standable(x, y):
				return Vector2i(cx * SIZE + x, cy * SIZE + y)
	return Vector2i(-1, -1)


func test_unload_forgets_nodes_and_nothing_else() -> void:
	_open()
	_scene.refresh_around(Vector2i(4, 4))
	var view := _scene.debug_summary()
	assert_eq((view.get("holders", []) as Array).has("overworld:0,0"), false, "far chunks drop")
	assert_eq(
		(_scene.streamer().summary().get("mutated_chunks", []) as Array).is_empty(),
		true,
		"with no mutations recorded"
	)


# --- Mutations ------------------------------------------------------------------


func test_destroy_unload_and_return_keeps_the_hole() -> void:
	_open()
	var victim := _blocking_cell()
	assert_ne(victim, Vector2i(-1, -1), "a blocking prop exists to destroy")
	var freed := _scene.destroy_at(victim)
	assert_eq(bool(freed.get("ok", false)), true, "destroying frees ground")
	assert_eq(_scene.is_standable(victim), true, "which is walkable now")
	_scene.refresh_around(Vector2i(4, 4))
	_scene.refresh_around(Vector2i(0, 0))
	assert_eq(_scene.is_standable(victim), true, "and still walkable after unload and return")


func _blocking_cell() -> Vector2i:
	var chunk := _scene.streamer().chunk_data("overworld", 0, 0, SIZE, SEED)
	for prop in chunk.props:
		var placement := prop as Dictionary
		if not bool(placement.get("blocking", false)):
			continue
		var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
		if chunk.standable(base.x, base.y):
			continue
		return Vector2i(base.x, base.y)
	return Vector2i(-1, -1)


# --- Determinism ------------------------------------------------------------------


func test_the_same_seed_answers_the_same_chunk() -> void:
	_open()
	var first := _scene.streamer().chunk_data("overworld", 0, 0, SIZE, SEED)
	var other := WorldmapScene.new()
	other.open(_graph, "overworld", _configs)
	var second := other.streamer().chunk_data("overworld", 0, 0, SIZE, SEED)
	assert_eq(
		JSON.stringify(first.to_dict()),
		JSON.stringify(second.to_dict()),
		"two scenes, one seed, one chunk"
	)
	other.free()


# --- Authored, hybrid, nested -------------------------------------------------------


func test_the_cave_is_authored_ground_with_procedural_rocks() -> void:
	_open()
	# Enter through a doorway, the way a player would: the cave's config
	# (authored terrain, no water, smaller chunks) only applies once the
	# scene actually opens that node. Generating "cave" data through the
	# overworld's config would prove nothing about nested nodes.
	var door := _walkable_in_chunk(0, 0)
	assert_ne(door, Vector2i(-1, -1), "a walkable cell exists")
	_graph.add_edge(
		{
			"from": "overworld",
			"to": "cave",
			"kind": &"doorway",
			"from_cell": door,
			"to_cell": Vector2i(1, 1)
		}
	)
	var route := _route(_scene.player_cell(), door)
	_walk(route.slice(0, route.size() - 1))
	var last: Vector2i = door - _scene.player_cell()
	var outcome := _scene.step(last.x, last.y)
	assert_eq(bool(outcome.get("traveled", false)), true, "the doorway travels")
	assert_eq(_scene.debug_summary().get("node"), "cave", "into the nested dungeon")
	assert_eq(_scene.debug_summary().get("chunk_size"), 6, "chunked at its own size")
	var chunk := _scene.streamer().chunk_data("cave", 0, 0, 6, 99)
	var flat := true
	for row in chunk.terrain:
		for arch in row as Array:
			if String(arch) != "ground_tile.base_ground":
				flat = false
	assert_eq(flat, true, "every terrain cell is the authored ground")
	assert_eq((chunk.props as Array).is_empty(), false, "and scatter still placed rocks")


# --- Portals ------------------------------------------------------------------------


func test_a_portal_crosses_to_a_differently_sized_universe() -> void:
	_open()
	var door := _first_walkable()
	assert_ne(door, Vector2i(-1, -1), "a walkable cell exists")
	_graph.add_edge(
		{
			"from": "overworld",
			"to": "far",
			"kind": &"portal",
			"from_cell": door,
			"to_cell": Vector2i(2, 1)
		}
	)
	# Walk to ADJACENT, then take the last step: entering the portal cell is
	# what travels, so walking through it would already be gone.
	var route := _route(_scene.player_cell(), door)
	assert_eq(route.is_empty(), false, "a route exists to the portal")
	_walk(route.slice(0, route.size() - 1))
	var last: Vector2i = door - _scene.player_cell()
	var outcome := _scene.step(last.x, last.y)
	assert_eq(bool(outcome.get("moved", false)), true, "the last step moves")
	assert_eq(bool(outcome.get("traveled", false)), true, "and entering travels")
	assert_eq(_scene.debug_summary().get("node"), "far", "to the far universe")
	assert_eq(_scene.debug_summary().get("chunk_size"), 12, "chunked at its own size")


# --- Regions --------------------------------------------------------------------------


func test_four_chunks_merge_into_one_region() -> void:
	_open()
	var outcome := _scene.render_region(
		"plaza", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	)
	assert_eq(bool(outcome.get("ok", false)), true, "the region renders")
	assert_eq(int(outcome.get("chunks", 0)), 4, "covering four chunks")
	var holders := _scene.debug_summary().get("holders", []) as Array
	assert_eq(holders.has("region:plaza"), true, "under one holder")
	_scene.refresh_around(Vector2i(0, 0))
	assert_eq(
		_scene.debug_summary().get("holders", []).has("region:plaza"),
		true,
		"which the streaming sweep does not free"
	)


# --- Building ---------------------------------------------------------------------------


func test_building_seals_open_ground_and_frees_again() -> void:
	_open()
	var cell := Vector2i(3, 0)
	assert_eq(_scene.is_standable(cell), true, "open ground to raise on")
	var raised := _scene.build_at(cell)
	assert_eq(bool(raised.get("ok", false)), true, "raising answers true")
	assert_eq(_scene.is_standable(cell), false, "and the cell seals")
	var again := _scene.build_at(cell)
	assert_eq(bool(again.get("ok", false)), false, "twice is refused")
	assert_eq(String(again.get("reason", "")), "no_ground", "as already sealed")
	var freed := _scene.destroy_at(cell)
	assert_eq(bool(freed.get("ok", false)), true, "while breaking a raised cell frees it")
	assert_eq(_scene.is_standable(cell), true, "open again")


func test_building_refuses_water_and_doorways() -> void:
	_open()
	var wet := Vector2i(2, 1)
	assert_eq(_scene.is_standable(wet), false, "water to refuse")
	var outcome := _scene.build_at(wet)
	assert_eq(bool(outcome.get("ok", false)), false, "water refuses")
	assert_eq(String(outcome.get("reason", "")), "no_ground", "by name")
	_graph.add_edge(
		{
			"from": "overworld",
			"to": "far",
			"kind": &"portal",
			"from_cell": Vector2i(4, 4),
			"to_cell": Vector2i(2, 1)
		}
	)
	assert_eq(_scene.is_standable(Vector2i(4, 4)), true, "a doorway to protect")
	var sealed := _scene.build_at(Vector2i(4, 4))
	assert_eq(bool(sealed.get("ok", false)), false, "doorways refuse")
	assert_eq(String(sealed.get("reason", "")), "sealed_way", "by name")


func test_a_raised_cell_survives_unload_and_return() -> void:
	_open()
	var cell := Vector2i(3, 0)
	_scene.build_at(cell)
	_scene.refresh_around(Vector2i(4, 4))
	_scene.refresh_around(Vector2i(0, 0))
	assert_eq(_scene.is_standable(cell), false, "still sealed after unload and return")
	var overlay := _scene.streamer().export_mutations()
	assert_eq(
		(overlay.get("overworld:0,0", {}) as Dictionary).has("3,0"),
		true,
		"recorded in the overlay the envelope carries"
	)
