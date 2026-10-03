extends TestCase

## Tests for PlayerAdapter: movement, interaction, states, save/load.

const INTERACTION_RANGE := 64.0
## `ActorStats` derives MOVE_SPEED as `100 + agility * 2`, and the fixture actor has
## no agility, so this is the exact speed the adapter must move at. Read from the
## actor rather than hardcoded so a stat-formula change fails one place.
const MOVE_SPEED := 100.0


func _make_adapter() -> PlayerAdapter:
	PlayerAdapter._ensure_input_actions()
	var actor := Actor.new(&"player", {Stat.PHYSIQUE: 20.0})
	var adapter := PlayerAdapter.new(actor)
	return adapter


## Puts the adapter in the scene tree. Needed only where a test reads or writes
## `global_position`, which is meaningless on a detached Node2D. Movement itself is
## asserted on `velocity` via `step_movement()`, which needs no tree — and no
## physics space, which a headless `SceneTree` test runner does not provide.
func _in_tree(adapter: PlayerAdapter) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(adapter)


func test_actor_wrapping() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 20.0})
	var adapter := PlayerAdapter.new(actor)
	assert_eq(adapter.actor(), actor, "actor reference exposed")


func test_initial_state() -> void:
	var adapter := _make_adapter()
	assert_eq(adapter.state(), PlayerAdapter.State.EXPLORATION, "starts in exploration")


func test_movement_input() -> void:
	var adapter := _make_adapter()
	Input.action_press("move_right")
	adapter.step_movement()
	Input.action_release("move_right")
	assert_almost_eq(adapter.velocity.x, MOVE_SPEED, "velocity moves right")
	assert_almost_eq(adapter.velocity.y, 0.0, "no vertical drift")


func test_movement_diagonal_normalized() -> void:
	var adapter := _make_adapter()
	Input.action_press("move_right")
	Input.action_press("move_down")
	adapter.step_movement()
	Input.action_release("move_right")
	Input.action_release("move_down")
	var expected := MOVE_SPEED / sqrt(2.0)
	assert_almost_eq(adapter.velocity.x, expected, "diagonal x normalized")
	assert_almost_eq(adapter.velocity.y, expected, "diagonal y normalized")


func test_move_to() -> void:
	var adapter := _make_adapter()
	adapter.global_position = Vector2.ZERO
	adapter.move_to(Vector2(100, 0))
	adapter.step_movement()
	assert_almost_eq(adapter.velocity.x, MOVE_SPEED, "velocity toward target")
	assert_eq(adapter.summary()["has_target"], true, "target retained en route")


func test_move_to_stops_at_target() -> void:
	var adapter := _make_adapter()
	adapter.global_position = Vector2.ZERO
	adapter.move_to(Vector2(2, 0))
	adapter.step_movement()
	assert_almost_eq(adapter.velocity.length(), 0.0, "no velocity at target")
	assert_eq(adapter.summary()["has_target"], false, "target cleared")


func test_interaction() -> void:
	var adapter := _make_adapter()
	adapter.global_position = Vector2.ZERO
	var npc := Node2D.new()
	npc.name = "Elder"
	npc.global_position = Vector2(32, 0)
	adapter.add_interactable(npc)
	var emitted := []
	adapter.interacted.connect(func(name): emitted.append(name))
	adapter.interact()
	assert_eq(emitted.size(), 1, "interact signal emitted")
	assert_eq(emitted[0], "Elder", "correct target name")


func test_interaction_out_of_range() -> void:
	var adapter := _make_adapter()
	_in_tree(adapter)
	adapter.global_position = Vector2.ZERO
	var npc := Node2D.new()
	npc.name = "FarAway"
	npc.global_position = Vector2(INTERACTION_RANGE + 10, 0)
	adapter.add_interactable(npc)
	var emitted := []
	adapter.interacted.connect(func(name): emitted.append(name))
	adapter.interact()
	assert_eq(emitted.size(), 0, "no signal when out of range")
	# Both nodes were parented for this test only. The runner shares one process
	# across every suite, so anything left under `root` outlives the test that made
	# it — and the NPC's own children with it.
	adapter.remove_interactable(npc)
	npc.free()
	adapter.get_parent().remove_child(adapter)
	adapter.free()


func test_state_transition() -> void:
	var adapter := _make_adapter()
	adapter.set_state(PlayerAdapter.State.COMBAT)
	assert_eq(adapter.state(), PlayerAdapter.State.COMBAT, "entered combat")
	adapter.set_state(PlayerAdapter.State.EXPLORATION)
	assert_eq(adapter.state(), PlayerAdapter.State.EXPLORATION, "exited combat")


func test_state_transition_signals() -> void:
	var adapter := _make_adapter()
	var states := []
	adapter.state_changed.connect(func(s): states.append(s))
	adapter.set_state(PlayerAdapter.State.COMBAT)
	adapter.set_state(PlayerAdapter.State.EXPLORATION)
	assert_eq(states.size(), 2, "two transitions emitted")
	assert_eq(states[0], PlayerAdapter.State.COMBAT, "first to combat")
	assert_eq(states[1], PlayerAdapter.State.EXPLORATION, "then to exploration")


func test_save_load() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(&"body", &"foundation"))
	var adapter := PlayerAdapter.new(actor)
	adapter.global_position = Vector2(100, 200)
	var data := adapter.to_dict()
	var restored := PlayerAdapter.from_dict(data)
	assert_almost_eq(restored.global_position.x, 100.0, "position x round trip")
	assert_almost_eq(restored.global_position.y, 200.0, "position y round trip")
	assert_eq(restored.actor().id, &"hero", "actor id round trip")
	assert_eq(restored.actor().realm(), &"foundation", "actor realm round trip")


func test_save_load_preserves_state() -> void:
	var adapter := _make_adapter()
	adapter.set_state(PlayerAdapter.State.COMBAT)
	var data := adapter.to_dict()
	var restored := PlayerAdapter.from_dict(data)
	assert_eq(restored.state(), PlayerAdapter.State.COMBAT, "state preserved")


func test_summary() -> void:
	var adapter := _make_adapter()
	var s := adapter.summary()
	assert_eq(s.has("position"), true, "summary has position")
	assert_eq(s.has("state"), true, "summary has state")
	assert_eq(s.has("actor_id"), true, "summary has actor_id")
	assert_eq(s.has("actor_realm"), true, "summary has actor_realm")
	assert_eq(s.has("interactable_count"), true, "summary has interactable_count")
	assert_eq(s.has("has_target"), true, "summary has has_target")
	assert_eq(s.has("map_bounds"), true, "summary has map_bounds")


func test_summary_primitives_only() -> void:
	var adapter := _make_adapter()
	var s := adapter.summary()
	for key in s.keys():
		var value = s[key]
		assert_eq(
			(
				typeof(value) == TYPE_ARRAY
				or typeof(value) == TYPE_FLOAT
				or typeof(value) == TYPE_INT
				or typeof(value) == TYPE_STRING
				or typeof(value) == TYPE_BOOL
			),
			true,
			"summary value is primitive: %s" % key
		)


func test_add_remove_interactable() -> void:
	var adapter := _make_adapter()
	var npc := Node2D.new()
	npc.name = "Test"
	adapter.add_interactable(npc)
	assert_eq(adapter.summary()["interactable_count"], 1, "interactable added")
	adapter.remove_interactable(npc)
	assert_eq(adapter.summary()["interactable_count"], 0, "interactable removed")


func test_set_map_bounds() -> void:
	var adapter := _make_adapter()
	var bounds := Rect2(0, 0, 2048, 2048)
	adapter.set_map_bounds(bounds)
	var s := adapter.summary()
	assert_eq(s["map_bounds"][2], 2048.0, "map bounds width set")
	assert_eq(s["map_bounds"][3], 2048.0, "map bounds height set")


func test_combat_speed_reduced() -> void:
	var adapter := _make_adapter()
	adapter.set_state(PlayerAdapter.State.COMBAT)
	Input.action_press("move_right")
	adapter.step_movement()
	Input.action_release("move_right")
	var expected := MOVE_SPEED * PlayerAdapter.COMBAT_SPEED_MULTIPLIER
	assert_almost_eq(adapter.velocity.x, expected, "combat speed reduced")
