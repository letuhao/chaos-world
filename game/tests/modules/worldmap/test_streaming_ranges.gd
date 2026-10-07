extends TestCase

## FOUR RANGES: data, simulation, scene, render — plus prediction and the
## transition hook. Ranges clamp to their invariants, prediction caches data
## without instantiating, render hides without freeing, and a non-seamless
## arrival yields to an installed hook or refuses by name.

const ENV := "mortal_greenwood"

var _born: Array = []


func setup() -> void:
	WorldmapApi.clear_transition()


func teardown() -> void:
	WorldmapApi.clear_transition()
	for scene in _born:
		if is_instance_valid(scene):
			if (scene as Node).get_parent() != null:
				(scene as Node).get_parent().remove_child(scene)
			(scene as Node).free()
	_born.clear()


func _configs(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 1234,
			"entry_row": 1,
			"data_radius": 2,
			"scene_radius": 1,
			"scatter": [],
		},
		"far":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 7,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter": [],
		},
	}
	for key in overrides.keys():
		(base["overworld"] as Dictionary)[key] = overrides[key]
	return base


func _graph() -> WorldmapGraph:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "far", "kind": &"universe", "parent": ""})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "far",
				"kind": &"portal",
				"from_cell": Vector2i(1, 1),
				"to_cell": Vector2i(2, 1),
			}
		)
	)
	return graph


func _open(configs: Dictionary) -> WorldmapScene:
	var scene := WorldmapScene.new()
	var outcome := scene.open(_graph(), "overworld", configs)
	assert_eq(bool(outcome.get("ok", false)), true, "the node opens")
	_born.append(scene)
	return scene


func test_ranges_clamp_to_their_invariants() -> void:
	var scene := _open(_configs({"scene_radius": 5, "sim_radius": 7, "render_radius": 9}))
	var summary := scene.streamer().summary()
	assert_eq(int(summary.get("scene_radius", -1)), 2, "scene clamps to data")
	assert_eq(int(summary.get("sim_radius", -1)), 2, "sim clamps to data")
	assert_eq(int(summary.get("render_radius", -1)), 2, "render clamps to scene")


func test_only_focus_chunks_simulate() -> void:
	var scene := _open(_configs({}))
	var streamer := scene.streamer()
	assert_eq(
		(streamer.summary().get("simulated", []) as Array).has("overworld:0,0"),
		true,
		"the focus chunk simulates"
	)
	assert_eq(streamer.is_simulated("overworld:9,9"), false, "while far chunks do not")


func test_prediction_caches_data_without_instantiating() -> void:
	var scene := _open(_configs({}))
	var streamer := scene.streamer()
	var before := int(streamer.summary().get("cached", 0))
	var loaded := (streamer.summary().get("loaded", []) as Array).size()
	var outcome := streamer.preload_toward(1, 0, 2)
	assert_eq(int(outcome.get("generated", 0)) >= 1, true, "chunks ahead generate")
	assert_eq(
		(streamer.summary().get("loaded", []) as Array).size(), loaded, "but nothing instantiates"
	)
	assert_eq(
		int(streamer.summary().get("cached", 0)),
		before + int(outcome.get("generated", 0)),
		"cache grows by exactly the prediction"
	)


func test_every_step_predicts_ahead() -> void:
	var scene := _open(_configs({}))
	var before := int(scene.streamer().summary().get("cached", 0))
	scene.step(1, 0)
	assert_eq(
		int(scene.streamer().summary().get("cached", 0)) > before,
		true,
		"walking east caches the chunks ahead"
	)


func test_render_hides_without_freeing() -> void:
	var scene := _open(_configs({"render_radius": 0}))
	var near := scene.get_node_or_null("chunk_0_0") as Node2D
	var far := scene.get_node_or_null("chunk_1_0") as Node2D
	assert_eq(near != null and far != null, true, "both holders instantiate")
	assert_eq(near.visible, true, "with the focus chunk shown")
	assert_eq(far.visible, false, "and the neighbor hidden but alive")


func test_a_non_seamless_arrival_without_a_hook_refuses() -> void:
	var configs := _configs({})
	(configs["far"] as Dictionary)["seamless"] = false
	var scene := _open(configs)
	var outcome := scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "no hook, no crossing")
	assert_eq(String(outcome.get("reason", "")), "no_transition_seam", "by name")
	assert_eq(String(scene.debug_summary().get("node", "")), "overworld", "holding position")


func test_a_transition_hook_names_both_sides_and_decides() -> void:
	var configs := _configs({})
	(configs["far"] as Dictionary)["seamless"] = false
	WorldmapApi.install_transition(Callable(self, "_refuse"))
	var scene := _open(configs)
	var outcome := scene.step(1, 0)
	assert_eq(bool(outcome.get("traveled", false)), false, "a refusing hook holds")
	assert_eq(String(outcome.get("reason", "")), "cutscene", "passing its reason through")
	WorldmapApi.install_transition(Callable(self, "_allow"))
	# Off and back on: the hook fires on ENTERING the far cell, and the
	# refused step already left the player standing on it.
	scene.step(-1, 0)
	var crossed := scene.step(1, 0)
	assert_eq(bool(crossed.get("traveled", false)), true, "an approving hook lets the cut through")
	assert_eq(String(scene.debug_summary().get("node", "")), "far", "to the far node")


func _refuse(from_node: String, to_node: String, _edge: Dictionary) -> Dictionary:
	assert_eq(from_node, "overworld", "the hook names where from")
	assert_eq(to_node, "far", "and where to")
	return {"ok": false, "reason": "cutscene"}


func _allow(_from_node: String, _to_node: String, _edge: Dictionary) -> Dictionary:
	return {"ok": true, "reason": ""}
