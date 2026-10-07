extends TestCase

## HOOK-GATED TRAVEL: who may cross an edge is decided outside the map system.
##
## An edge without a hook passes; an edge whose hook has an installed
## evaluator asks it; an edge whose hook has NOTHING installed refuses
## `unknown_gate` rather than passing. The scene asks the gate BEFORE moving
## any state, so a refused crossing leaves the player where they stood.

const ENV := "mortal_greenwood"

var _scene: WorldmapScene = null


func setup() -> void:
	WorldmapGates.clear()
	_scene = null


func teardown() -> void:
	WorldmapGates.clear()
	if _scene != null and is_instance_valid(_scene):
		if _scene.get_parent() != null:
			_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null


func test_an_edge_without_a_hook_passes() -> void:
	var outcome := WorldmapApi.can_traverse({"from": "a", "to": "b", "kind": &"doorway"})
	assert_eq(bool(outcome.get("ok", false)), true, "no hook means no gate")


func test_a_hook_with_nothing_installed_refuses_by_name() -> void:
	var outcome := WorldmapApi.can_traverse(
		{"from": "a", "to": "b", "kind": &"portal", "hook": "toll_bridge"}
	)
	assert_eq(bool(outcome.get("ok", false)), false, "an unwired gate does not pass")
	assert_eq(String(outcome.get("reason", "")), "unknown_gate", "and says so by name")


func test_register_refuses_an_empty_hook_and_a_dead_callable() -> void:
	assert_eq(
		String(WorldmapGates.register("", Callable(self, "_allow")).get("reason", "")),
		"empty_hook",
		"an empty hook is refused"
	)
	assert_eq(
		String(WorldmapGates.register("toll_bridge", Callable()).get("reason", "")),
		"dead_evaluator",
		"and so is a dead Callable"
	)


func test_an_installed_evaluator_decides_and_sees_the_context() -> void:
	WorldmapGates.register("toll_bridge", Callable(self, "_toll"))
	var edge := {"from": "a", "to": "b", "kind": &"portal", "hook": "toll_bridge"}
	var poor := WorldmapApi.can_traverse(edge, {"coins": 0})
	assert_eq(bool(poor.get("ok", false)), false, "without the toll, no crossing")
	assert_eq(String(poor.get("reason", "")), "unpaid_toll", "naming the price")
	var rich := WorldmapApi.can_traverse(edge, {"coins": 5})
	assert_eq(bool(rich.get("ok", false)), true, "with the toll paid, the way opens")


func test_a_bool_verdict_counts_and_a_garbage_verdict_refuses() -> void:
	WorldmapGates.register("open_door", Callable(self, "_allow"))
	assert_eq(
		bool(WorldmapApi.can_traverse({"hook": "open_door"}, {}).get("ok", false)),
		true,
		"a bool true is an approval"
	)
	WorldmapGates.register("broken_gate", Callable(self, "_garbage"))
	var outcome := WorldmapApi.can_traverse({"hook": "broken_gate"}, {})
	assert_eq(
		bool(outcome.get("ok", false)), false, "a verdict that is neither bool nor dict refuses"
	)
	assert_eq(String(outcome.get("reason", "")), "bad_verdict", "by name")


func test_a_refused_crossing_leaves_the_player_where_they_stood() -> void:
	_open_gated()
	# The gate sits on (1,1), one step east of the entry: measured-open ground,
	# so the test walks nowhere it has not already proven.
	var outcome := _scene.step(1, 0)
	assert_eq(bool(outcome.get("moved", false)), true, "the step onto the gate cell moves")
	assert_eq(bool(outcome.get("traveled", false)), false, "but the gate holds")
	assert_eq(String(outcome.get("reason", "")), "unknown_gate", "naming the unwired hook")
	assert_eq(_scene.debug_summary().get("node"), "overworld", "on the same node")
	WorldmapGates.register("cave_key", Callable(self, "_allow"))
	_scene.step(-1, 0)
	var passed := _scene.step(1, 0)
	assert_eq(
		bool(passed.get("traveled", false)),
		true,
		"and a wired approval carries through: %s" % String(passed.get("reason", ""))
	)
	assert_eq(_scene.debug_summary().get("node"), "cave", "into the nested node")


func _toll(edge: Dictionary, context: Dictionary) -> Dictionary:
	assert_eq(String(edge.get("hook", "")), "toll_bridge", "the evaluator sees the edge it gates")
	if int(context.get("coins", 0)) >= 5:
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unpaid_toll"}


func _allow(_edge: Dictionary, _context: Dictionary) -> bool:
	return true


func _garbage(_edge: Dictionary, _context: Dictionary) -> int:
	return 7


func _configs() -> Dictionary:
	return {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 1234,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter": [],
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
			"authored_terrain": [],
			"scatter": [],
		},
	}


func _open_gated() -> void:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "cave",
				"kind": &"doorway",
				"from_cell": Vector2i(1, 1),
				"to_cell": Vector2i(1, 1),
				"hook": "cave_key",
			}
		)
	)
	_scene = WorldmapScene.new()
	var outcome := _scene.open(graph, "overworld", _configs())
	assert_eq(bool(outcome.get("ok", false)), true, "the gated node opens")
