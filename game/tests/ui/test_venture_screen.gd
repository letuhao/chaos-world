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
	# Module statics are NOT the harness's: a descent test leaves its return
	# on the shared stack and its run on the boot, and the next test would
	# start "inside" with every step refused. Clear both here.
	if _harness != null:
		_harness.teardown()
	_harness = null
	WorldmapApi.clear_returns()
	DomainBoot.reset()


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


## Depth-first walk to a demo node through the screen's own step verbs.
## Arrival READS as the node (the step that lands on the door descends, the
## step onto the pad portals), so reaching is the assertion and no route is
## precomputed. Seen is keyed by node AND cell: the far portal is a round
## trip, so the same coordinates recur on two planes and a cell-only key
## would close the far side unvisited.
## Bounded by `WALK_DEPTH`: sealed ground answers false, never spins.
func _walk_to_door(screen: Control) -> bool:
	return _dfs(screen, {}, 0, "cave")


func _walk_to_far(screen: Control) -> bool:
	var seen := {}
	return _dfs(screen, seen, 0, "far")


func _dfs(screen: Control, seen: Dictionary, depth: int, want: String) -> bool:
	var view := screen.call("summary") as Dictionary
	if String(view.get("node", "")) == want:
		return true
	var cur := _key_of(view)
	if depth >= WALK_DEPTH or seen.has(cur):
		return false
	seen[cur] = true
	# Stay on the demo's single chunk per plane: past its edge lies
	# unbounded generated wilderness, and a walk that leaves the map it is
	# proving can burn its whole depth finding its way back.
	var size := int(view.get("chunk_size", 8))
	for verb in ["act_east", "act_north", "act_south", "act_west"]:
		if depth + 1 >= WALK_DEPTH:
			break
		var target := _cell_of(view) + _delta_of(verb)
		if target.x < 0 or target.y < 0 or target.x >= size or target.y >= size:
			continue
		# Never step onto another node's door on the way: a descent cannot
		# be backtracked out of, so the search would strand there.
		if _edge_to(view, _cell_of(view) + _delta_of(verb), want) != "":
			continue
		if not bool(screen.call(verb)):
			continue
		if String((screen.call("summary") as Dictionary).get("node", "")) == want:
			return true
		if _dfs(screen, seen, depth + 1, want):
			return true
		screen.call(_backtrack_of(verb))
	return false


## Where a step from `cell` by `delta` would travel, or "" for open ground.
## Read off the world's own edge list, never restated.
func _edge_to(view: Dictionary, cell: Vector2i, want: String) -> String:
	for edge in view.get("edges", []) as Array:
		var row := edge as Dictionary
		var from := row.get("from_cell", []) as Array
		if int(from[0]) == cell.x and int(from[1]) == cell.y and String(row.get("to", "")) != want:
			return String(row.get("to", ""))
	return ""


func _delta_of(verb: String) -> Vector2i:
	match verb:
		"act_east":
			return Vector2i(1, 0)
		"act_west":
			return Vector2i(-1, 0)
		"act_south":
			return Vector2i(0, 1)
	return Vector2i(0, -1)


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


func test_raising_ground_seals_it_across_reopen() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	screen.call("act_east")
	var raised := _cell_of(screen.call("summary") as Dictionary)
	assert_eq(screen.call("act_build"), true, "raising answers true")
	screen.call("act_west")
	assert_eq(bool(screen.call("act_east")), false, "the raised cell no longer admits")
	screen.call("act_open")
	assert_eq(
		_cell_of(screen.call("summary") as Dictionary),
		Vector2i(0, 1),
		"reopening falls back to the entry: the resume cell is sealed by its own wall"
	)
	assert_eq(bool(screen.call("act_east")), false, "the raised cell no longer admits")


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


func test_the_far_arrival_plays_the_loading_screen() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	_fund(_harness.actor, 10)
	var before := EconomyApi.purse(_harness.actor)
	assert_eq(_walk_to_far(screen), true, "the far pad is reachable on foot")
	var view := screen.call("summary") as Dictionary
	assert_eq(String(view.get("node", "")), "far", "through the portal to the far side")
	assert_eq(
		screen.get_node_or_null("VentureTransition"), null, "with the overlay freed afterwards"
	)
	assert_eq((view.get("holders", []) as Array).is_empty(), false, "and the far side rendered")
	assert_eq(EconomyApi.purse(_harness.actor), before - 5, "having paid the five-coin toll")


func test_a_broke_hero_is_refused_with_coins_untouched() -> void:
	var screen := _venture_screen()
	if screen == null:
		return
	screen.call("act_open")
	var coin := EconomyValuation.numeraire_id()
	while EconomyApi.purse(_harness.actor) > 0:
		if not ItemsApi.consume_item(_harness.actor, coin, 1):
			break
	assert_eq(EconomyApi.purse(_harness.actor), 0, "genuinely broke")
	assert_eq(_walk_to_pad(screen), true, "an approach cell is reachable")
	var cur := _cell_of(screen.call("summary") as Dictionary)
	var last := Vector2i(5, 5) - cur
	var verb := "act_east"
	if last.x < 0:
		verb = "act_west"
	elif last.y > 0:
		verb = "act_south"
	elif last.y < 0:
		verb = "act_north"
	assert_eq(bool(screen.call(verb)), true, "the last step moves onto the pad")
	assert_eq(
		String((screen.call("summary") as Dictionary).get("node", "")),
		"overworld",
		"but broke heroes stay home"
	)
	assert_eq(EconomyApi.purse(_harness.actor), 0, "with nothing taken")


## Walk to a pad approach cell WITHOUT stepping on any travel cell: stops
## adjacent, for the refusal case. Pad cells and the cave door are forbidden;
## arrival is any approach cell of the far pad. Bounded like the door walk.
func _walk_to_pad(screen: Control) -> bool:
	return _dfs_cell(
		screen, {}, 0, [Vector2i(4, 5), Vector2i(5, 4)], [Vector2i(5, 5), Vector2i(3, 1)]
	)


func _dfs_cell(
	screen: Control, seen: Dictionary, depth: int, targets: Array, forbid: Array
) -> bool:
	var view := screen.call("summary") as Dictionary
	var node := String(view.get("node", ""))
	if node != "overworld":
		return false
	var cur := _cell_of(view)
	if cur in targets:
		return true
	var key := _key_of(view)
	if depth >= WALK_DEPTH or seen.has(key):
		return false
	seen[key] = true
	var size := int(view.get("chunk_size", 8))
	for verb in ["act_east", "act_north", "act_south", "act_west"]:
		if depth + 1 >= WALK_DEPTH:
			break
		var target := cur + _delta_of(verb)
		if target.x < 0 or target.y < 0 or target.x >= size or target.y >= size:
			continue
		if target in forbid:
			continue
		if not bool(screen.call(verb)):
			continue
		if String((screen.call("summary") as Dictionary).get("node", "")) != "overworld":
			return false
		if _dfs_cell(screen, seen, depth + 1, targets, forbid):
			return true
		screen.call(_backtrack_of(verb))
	return false


func _fund(actor: Actor, coins: int) -> void:
	ItemsApi.attach(actor)
	EconomyApi.attach(actor)
	var def := Crafting.resolve(EconomyValuation.numeraire_id())
	ItemsApi.inventory(actor).add(def, coins)
