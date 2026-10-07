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
## The demo doorway in the overworld, read off the boot's own graph rather
## than restated — a second copy of the graph is a second thing that can be wrong.
const DOOR := Vector2i(3, 1)
## Depth ceiling for the walk below. Two planes (8x8 overworld, 12x12 far)
## plus a portal bounce between them; this is slack with a visited set behind
## it, and it is what keeps the walk from being an unbounded loop the moment
## the ground seals.
const WALK_DEPTH := 160

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


func test_stepping_through_the_doorway_descends_into_a_real_run() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	assert_eq(_walk_to_door(screen), true, "the demo doorway is reachable on foot")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("node", "")), "cave", "through the doorway into the cave node")
	assert_eq(
		String((view.get("domain", {}) as Dictionary).get("template", "")),
		"ember_grotto",
		"which is a run in the authored template, not painted ground"
	)
	assert_eq(
		DomainApi.rooms(_harness.actor).is_empty(),
		false,
		"and the run is REAL: rooms stand on the root's own actor"
	)


func test_returning_stands_back_on_the_doorway_cell() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	if not _walk_to_door(screen):
		return
	assert_eq(screen.call("act_return"), true, "Return answers true")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("node", "")), "overworld", "back above ground")
	assert_eq(_cell_of(view), DOOR, "on the exact doorway cell left from")
	assert_eq(DomainApi.rooms(_harness.actor).is_empty(), true, "with the run gone from the actor")


## Depth-first walk to the demo doorway through the screen's own step verbs.
## Arrival READS as the cave node (the step that lands on the door descends),
## so reaching is the assertion and no route is precomputed. Seen is keyed by
## node AND cell: the far portal is a round trip, so the same coordinates recur
## on two planes and a cell-only key would close the far side unvisited.
## Bounded by `WALK_DEPTH`: sealed ground answers false, never spins.
func _walk_to_door(screen: Control) -> bool:
	return _dfs(screen, {}, 0)


func _dfs(screen: Control, seen: Dictionary, depth: int) -> bool:
	var view := screen.call("summary") as Dictionary
	if String(view.get("node", "")) == "cave":
		return true
	var cur := _key_of(view)
	if depth >= WALK_DEPTH or seen.has(cur):
		return false
	seen[cur] = true
	for verb in ["act_east", "act_north", "act_south", "act_west"]:
		if depth + 1 >= WALK_DEPTH:
			break
		if not bool(screen.call(verb)):
			continue
		if String((screen.call("summary") as Dictionary).get("node", "")) == "cave":
			return true
		if _dfs(screen, seen, depth + 1):
			return true
		screen.call(_backtrack_of(verb))
	return false


func _key_of(view: Dictionary) -> String:
	var cell := view.get("player_cell", [0, 0]) as Array
	return "%s:%d,%d" % [String(view.get("node", "")), int(cell[0]), int(cell[1])]


func _backtrack_of(verb: String) -> StringName:
	match verb:
		"act_east":
			return &"act_west"
		"act_west":
			return &"act_east"
		"act_south":
			return &"act_north"
	return &"act_south"


func _cell_of(view: Dictionary) -> Vector2i:
	var cell := view.get("player_cell", [0, 0]) as Array
	return Vector2i(int(cell[0]), int(cell[1]))


func test_debug_is_dark_until_toggled() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("debug_text", "x")), "", "no overlay before the toggle")
	assert_eq(screen.call("act_debug"), true, "the toggle answers true")
	view = screen.call("summary") as Dictionary
	var text := String(view.get("debug_text", ""))
	assert_eq(text.contains("node overworld"), true, "naming the node")
	assert_eq(text.contains("seed 1234"), true, "and its seed")
	assert_eq(text.contains("terrain"), true, "listing passes")
	assert_eq(text.contains("collision"), true, "to the last writer")
	assert_eq(screen.call("act_debug"), true, "toggling back answers true")
	assert_eq(
		String((screen.call("summary") as Dictionary).get("debug_text", "x")),
		"",
		"and darkens again"
	)


func test_debug_names_edges_pois_and_ranges() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	screen.call("act_debug")
	var view := screen.call("summary") as Dictionary
	var text := String(view.get("debug_text", ""))
	assert_eq(text.contains("edges 2"), true, "door and portal with their cells")
	assert_eq(text.contains("ranges data 2 sim"), true, "with the ranges in force")
	assert_eq(text.contains("pois "), true, "and a POI count")
	assert_eq((view.get("passes", []) as Array).size(), 13, "across the whole pass set")
	var first_edge := (view.get("edges", []) as Array)[0] as Dictionary
	assert_eq((first_edge.get("from_cell", []) as Array).size(), 2, "edges carry cells")


func test_debug_without_a_world_refuses() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	assert_eq(screen.call("act_debug"), false, "nothing standing, nothing to paint")


func test_reopening_resumes_where_the_player_stood() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	screen.call("act_east")
	var cell := _cell_of(screen.call("summary") as Dictionary)
	assert_ne(cell, Vector2i(0, 1), "the step moved")
	screen.call("act_open")
	assert_eq(
		_cell_of(screen.call("summary") as Dictionary), cell, "and reopening resumes the cell"
	)


## Walk the open ground until the wild answers, bounded: marker density
## makes this a short stroll, and the cap makes sealed ground an answer
## rather than a spin.
func _walk_till_encounter(screen: Control) -> String:
	var verbs := ["act_east", "act_south", "act_west", "act_north"]
	for attempt in 48:
		screen.call(verbs[attempt % verbs.size()])
		var pending := String((screen.call("summary") as Dictionary).get("pending_encounter", ""))
		if not pending.is_empty():
			return pending
	return ""


func test_stepping_on_wild_ground_offers_a_real_encounter() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	var pending := _walk_till_encounter(screen)
	assert_ne(pending, "", "the wild answered with a real encounter id")
	var view := screen.call("summary") as Dictionary
	assert_eq((view.get("pending_fates", []) as Array).is_empty(), false, "carrying fate choices")
	assert_ne(String(view.get("encounter_text", "")), "", "and the row says so")


func test_answering_a_fate_earns_it_and_clears_the_offer() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	if _walk_till_encounter(screen).is_empty():
		return
	assert_eq(screen.call("act_fate_first"), true, "the first fate answers")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("pending_encounter", "x")), "", "clearing the offer")
	assert_ne(String(view.get("message_text", "")), "", "with the earned fate named")


func test_walking_away_dismisses_without_earning() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	if _walk_till_encounter(screen).is_empty():
		return
	assert_eq(screen.call("act_dismiss"), true, "walking away answers true")
	assert_eq(
		String((screen.call("summary") as Dictionary).get("pending_encounter", "x")),
		"",
		"clearing the offer without a fate"
	)
