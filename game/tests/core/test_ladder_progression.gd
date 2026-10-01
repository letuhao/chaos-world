extends TestCase

## ADR 0003: a ladder progression advances one rank when progress reaches threshold.


func test_cannot_advance_below_threshold() -> void:
	var state := PathState.new(&"qi", &"refining")
	state.progress = 0.5
	var model := LadderProgression.new()
	assert_eq(model.can_advance(state, {"threshold": 1.0}), false, "below threshold")


func test_advance_moves_rank_and_carries_progress() -> void:
	var state := PathState.new(&"qi", &"refining")
	state.progress = 1.5
	var model := LadderProgression.new()
	assert_eq(model.can_advance(state, {"threshold": 1.0}), true, "at threshold")
	model.advance(state, {"threshold": 1.0, "next_rank": &"foundation"})
	assert_eq(state.rank_id, &"foundation", "rank advanced")
	assert_eq(state.stage, 1, "stage incremented")
	assert_almost_eq(state.progress, 0.5, "progress carried")
