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
	state.state = &"damaged"
	assert_eq(state.is_open(), true, "damaged is open")


func test_is_damaged() -> void:
	var state := MeridianState.new()
	assert_eq(state.is_damaged(), false, "closed is not damaged")
	state.state = &"open"
	assert_eq(state.is_damaged(), false, "open is not damaged")
	state.state = &"damaged"
	assert_eq(state.is_damaged(), true, "damaged is damaged")


func test_get_bonus() -> void:
	var state := MeridianState.new()
	assert_almost_eq(state.get_bonus(), 1.0, "closed bonus")
	state.state = &"open"
	assert_almost_eq(state.get_bonus(), 1.0, "open bonus")
	state.state = &"expanded"
	assert_almost_eq(state.get_bonus(), 1.0, "expanded bonus")
	state.state = &"strengthened"
	assert_almost_eq(state.get_bonus(), 1.0, "strengthened bonus")
	state.state = &"damaged"
	assert_almost_eq(state.get_bonus(), 0.5, "damaged bonus")
