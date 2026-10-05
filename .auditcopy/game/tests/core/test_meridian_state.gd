extends TestCase

## ADR 0017: MeridianState tracks per-meridian runtime state.


func test_initial_state_is_closed() -> void:
	var state := MeridianState.new()
	assert_eq(state.state, &"closed", "initial state")


func test_is_open() -> void:
	var state := MeridianState.new()
	assert_eq(state.is_open(), false, "closed is not open")
	state.state = &"open"
	assert_eq(state.is_open(), true, "open is open")
	state.state = &"expanded"
	assert_eq(state.is_open(), true, "expanded is open")
	state.state = &"strengthened"
	assert_eq(state.is_open(), true, "strengthened is open")
	# Injury is a flag, not a state: a wounded channel stays open.
	state.injured = true
	assert_eq(state.is_open(), true, "injured is still open")


func test_is_injured() -> void:
	var state := MeridianState.new()
	assert_eq(state.is_injured(), false, "closed is not injured")
	state.state = &"open"
	assert_eq(state.is_injured(), false, "open is not injured")
	state.injured = true
	assert_eq(state.is_injured(), true, "injured is injured")


func test_get_bonus() -> void:
	var state := MeridianState.new()
	assert_almost_eq(state.get_bonus(), 1.0, "closed bonus")
	state.state = &"open"
	assert_almost_eq(state.get_bonus(), 1.0, "open bonus")
	state.state = &"expanded"
	assert_almost_eq(state.get_bonus(), 1.0, "expanded bonus")
	state.state = &"strengthened"
	assert_almost_eq(state.get_bonus(), 1.0, "strengthened bonus")
	state.injured = true
	assert_almost_eq(state.get_bonus(), 0.5, "injured bonus")
