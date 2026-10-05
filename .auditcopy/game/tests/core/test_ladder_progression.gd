extends TestCase

## ADR 0003/0005: ladder progression advances along the shared realm ladder.


func test_cannot_advance_below_threshold() -> void:
	var state := PathState.new(&"qi", &"qi_refining")
	state.progress = 0.5
	var model := LadderProgression.new()
	assert_eq(model.can_advance(state, {"threshold": 1.0}), false, "below threshold")


func test_advance_moves_to_next_realm() -> void:
	var state := PathState.new(&"qi", &"qi_refining")
	state.progress = 1.5
	var model := LadderProgression.new()
	assert_eq(model.can_advance(state, {"threshold": 1.0}), true, "at threshold")
	model.advance(state, {"threshold": 1.0})
	assert_eq(state.rank_id, &"foundation", "advanced along the ladder")
	assert_eq(state.stage, 1, "stage incremented")
	assert_almost_eq(state.progress, 0.5, "progress carried")


func test_cannot_advance_past_top() -> void:
	var state := PathState.new(&"qi", &"primordial_origin")
	state.progress = 2.0
	var model := LadderProgression.new()
	model.advance(state, {"threshold": 1.0})
	assert_eq(state.rank_id, &"primordial_origin", "stays at the top of the ladder")
