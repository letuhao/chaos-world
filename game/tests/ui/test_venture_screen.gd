extends TestCase

## PROOF AT THE PRODUCTION SEAM: the venture route opens a walkable generated
## world under the mounted screen.
##
## Every claim here is made on nodes the composition root itself parented:
## navigate to the route through the real `navigate_to`, press the screen's
## own verbs, and assert on the tree the root built. A screen this suite built
## itself could never prove the root bound it.

const VENTURE_ROUTE := &"venture"
const VENTURE_NODE := "VentureScreen"
const WORLD_NODE := "VentureWorld"

var _harness: SeamHarness = null


func teardown() -> void:
	# The harness owns the mounted root: `mount_new` tears the previous one
	# down, and freeing a screen out from under its stack leaves the stack
	# toggling visibility on a freed node. So teardown is the harness's.
	if _harness != null:
		_harness.teardown()
	_harness = null


func _seam() -> SeamHarness:
	if _harness != null:
		return _harness
	_harness = SeamHarness.mount_new()
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return _harness if _harness.boot_error == "" else null


func _venture_screen() -> Control:
	var harness := _seam()
	if harness == null:
		return null
	var moved := harness.navigate(VENTURE_ROUTE)
	assert_eq(
		bool(moved["ok"]),
		true,
		"the venture route is reachable: %s" % String(moved.get("note", ""))
	)
	if not bool(moved["ok"]):
		return null
	var live := harness.live_screen()
	assert_eq(live != null, true, "the route left a live screen")
	if live == null:
		return null
	assert_eq(String(live.name), VENTURE_NODE, "and the root named it for the route it serves")
	return live


func _world_under(screen: Control) -> Node:
	return screen.get_node_or_null("%WorldHolder/" + WORLD_NODE)


func test_the_route_lists_places_before_anything_stands() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	var action := ScreenRoutes.action_of(VENTURE_ROUTE)
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	var view := screen.call("summary") as Dictionary
	assert_eq(view.is_empty(), false, "the bound screen has a summary")
	assert_eq(bool(view.get("open", true)), false, "with nothing standing yet")
	assert_eq((view.get("nodes", []) as Array).is_empty(), false, "but the demo places are listed")


func test_opening_stands_a_world_under_the_mounted_screen() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	assert_eq(screen.call("act_open"), true, "the screen's own Open stands a world")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("node", "")), "overworld", "on the overworld")
	assert_eq(_world_under(screen) != null, true, "parented under the mounted screen")
	assert_eq(
		(view.get("holders", []) as Array).has("overworld:0,0"),
		true,
		"with the entry chunk rendered"
	)


func test_stepping_moves_the_player_one_cell() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	var before := (
		((screen.call("summary") as Dictionary).get("player_cell", []) as Array).duplicate()
	)
	var moved := false
	for verb in ["act_south", "act_north", "act_east", "act_west"]:
		if bool(screen.call(verb)):
			moved = true
			break
	assert_eq(moved, true, "at least one direction off the entry cell is open ground")
	var after := (screen.call("summary") as Dictionary).get("player_cell", []) as Array
	assert_ne(str(after), str(before), "and the player cell changed")


func test_break_reports_what_it_did() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	screen.call("act_destroy")
	var view := screen.call("summary") as Dictionary
	assert_ne(String(view.get("message_text", "")), "", "the verb reports either way")
	assert_eq(bool(view.get("open", false)), true, "and the world still stands")


func test_closing_frees_the_world() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	assert_eq(screen.call("act_close"), true, "Close answers true")
	assert_eq(_world_under(screen), null, "and the world is gone from the tree")
	assert_eq(
		bool((screen.call("summary") as Dictionary).get("open", true)),
		false,
		"and the read says so"
	)
