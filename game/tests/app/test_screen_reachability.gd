extends TestCase

## PROOF AT THE SEAM: every screen the UI program ships is reachable from the
## running app by a concrete user action, and becomes the live screen.
##
## This suite replaces `test_item_workbench_app_screens.gd`, which asserted
## reachability by pushing **freshly instantiated** copies of the socket forge and
## the loot encounter onto the stack. That proved a scene file parses; no player can
## do what it did. Worse, `open_screen()` — the method it exercised — had no caller
## anywhere in `src/` (BL-0121), so the test was the only consumer of a route that
## did not exist.
##
## Every assertion here is made against a node the composition root itself parented
## under the mounted app. A screen the test instantiates itself can never satisfy one
## of them, so the original false proof cannot come back in this shape.
##
## The expectations are discovered, not restated: screens come from the filesystem
## and routes from the shipped route table, so the only thing this suite holds is the
## rule they must satisfy. That is deliberate — a second copy of the route table in a
## test is a second thing that can be wrong.

const HUB_METHODS := [&"routes", &"navigate_to", &"current_route"]
## Where a screen a player can reach has to be named, outside the test suite.
const PROGRAM_ROOTS := ["res://src", "res://scenes"]
const SUFFIXES := [".gd", ".tscn"]
## The composition root's own script: where a door into the screen stack lives.
const APP_SCRIPT := "res://src/app/item_workbench_app.gd"
## A public method that opens a screen. Each needs a caller in `src/`, or it is a
## door only a test can walk through — the shape BL-0121 was filed about.
const DOOR_PREFIXES := ["mount_", "open_", "push_", "show_"]


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## One counted failure per missing hub method, then a boolean. A missing seam is a
## failure that names itself, never a `call()` on an absent method: that is a script
## error, which aborts the function and lets the suite report the rest of its
## assertions green.
func _seam_is_live() -> bool:
	if SeamHarness.live == null or SeamHarness.live.app == null:
		_boot()
	var harness := SeamHarness.live
	if harness == null or harness.app == null or harness.boot_error != "":
		assert_eq(harness != null and harness.boot_error, "", "the real ItemWorkbenchApp boots")
		return false
	for method in HUB_METHODS:
		assert_eq(
			harness.app.has_method(method),
			true,
			"MISSING SEAM: ItemWorkbenchApp has no %s() navigation seam (BL-0118, BL-0121)" % method
		)
	return true


# --- The route table is the seam --------------------------------------------


func test_the_composition_root_publishes_a_route_table() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var listed := harness.routes()
	assert_eq(listed["note"], "", "routes() is readable")
	assert_ne((listed["routes"] as Array).size(), 0, "and it is not empty")
	assert_eq(
		(listed["routes"] as Array).size(),
		ScreenRoutes.all().size(),
		"the app publishes the whole route table, not a subset"
	)
	for route in listed["routes"] as Array:
		assert_ne(
			String((route as Dictionary).get("id", "")), "", "every published route has an id"
		)
		assert_ne(
			String((route as Dictionary).get("scene", "")), "", "and names the scene it mounts"
		)


func test_every_screen_scene_the_ui_program_ships_has_a_route() -> void:
	var shipped := SeamHarness.screen_scene_paths()
	assert_ne(shipped.size(), 0, "the UI program ships screens")
	for scene_path in shipped:
		var route := SeamHarness.route_for_scene(scene_path)
		assert_ne(
			String(route),
			"",
			(
				(
					"MISSING SEAM: %s is shipped but the route table names no route for it, so it "
					% scene_path
				)
				+ "can only ever be instantiated by a test"
			)
		)


func test_every_route_points_at_a_scene_that_exists_and_is_shipped() -> void:
	for route in ScreenRoutes.all():
		var route_id := StringName(route.get("id", ""))
		var scene_path := String(route.get("scene", ""))
		assert_ne(String(route_id), "", "every route carries an id")
		assert_eq(ResourceLoader.exists(scene_path), true, "route '%s' scene exists" % route_id)
		assert_eq(
			SeamHarness.screen_scene_paths().has(scene_path),
			true,
			"route '%s' names %s, which the UI program does not ship" % [route_id, scene_path]
		)
		assert_eq(
			SeamHarness.route_for_scene(scene_path),
			route_id,
			"the table agrees with itself about which route mounts %s" % scene_path
		)


func test_exactly_one_route_is_the_home_screen() -> void:
	var roots := 0
	for route in ScreenRoutes.all():
		if bool(route.get("root", false)):
			roots += 1
	assert_eq(roots, 1, "exactly one route is the home every other screen stacks over")


func test_every_route_has_its_own_input_action() -> void:
	# A route reachable only by a button is a route a keyboard player cannot reach.
	var actions: Dictionary = {}
	for route in ScreenRoutes.all():
		var route_id := StringName(route.get("id", ""))
		var action := ScreenRoutes.action_of(route_id)
		assert_ne(String(action), "", "route '%s' names an input action" % route_id)
		assert_eq(
			actions.has(String(action)),
			false,
			(
				"route '%s' does not share input action '%s' with route '%s'"
				% [route_id, action, actions.get(String(action), "")]
			)
		)
		actions[String(action)] = String(route_id)
		assert_eq(
			InputMap.has_action(action),
			true,
			"route '%s' is bound to input action '%s'" % [route_id, action]
		)


# --- The matrix: route -> mounted -> live -----------------------------------


func test_every_route_mounts_its_screen_and_makes_it_the_live_screen() -> void:
	if not _seam_is_live():
		return
	var harness := SeamHarness.live
	for scene_path in SeamHarness.screen_scene_paths():
		var route_id := SeamHarness.route_for_scene(scene_path)
		if route_id.is_empty():
			continue
		var moved := harness.navigate(route_id)
		assert_eq(
			moved["ok"],
			true,
			(
				"route '%s' (%s) is not reachable: %s"
				% [route_id, scene_path.get_file(), moved["note"]]
			)
		)
		if not bool(moved["ok"]):
			continue
		var live := harness.live_screen()
		assert_ne(live, null, "route '%s' left a live screen" % route_id)
		if live == null:
			continue
		# The scene file path is the whole point: it is the mounted screen's own
		# identity, so a freshly instantiated copy cannot satisfy it.
		assert_eq(
			live.scene_file_path,
			scene_path,
			(
				"route '%s' shows %s, not the screen it claims to mount"
				% [route_id, live.scene_file_path]
			)
		)
		assert_eq(
			harness.app.is_ancestor_of(live),
			true,
			"route '%s' shows a screen mounted under the running app" % route_id
		)
		assert_eq(
			harness.bound_actor(live),
			harness.actor,
			"route '%s' shows a screen bound to the app's own actor" % route_id
		)
		var view := harness.stack.summary()
		assert_eq(
			view["visible"],
			[String(live.name)],
			"route '%s' makes %s the only visible screen" % [route_id, live.name]
		)
		assert_eq(
			view["input_names"],
			[String(live.name)],
			"route '%s' gives %s the input, as the live screen" % [route_id, live.name]
		)
		assert_eq(
			String(view["current"]),
			ScreenRoutes.node_of(route_id),
			"and the live screen is named for the route it serves"
		)


func test_navigating_reports_the_route_it_is_on() -> void:
	if not _seam_is_live():
		return
	var harness := SeamHarness.live
	for route in ScreenRoutes.all():
		var route_id := StringName(route.get("id", ""))
		var moved := harness.navigate(route_id)
		if not bool(moved["ok"]):
			continue  # already reported, with the seam named, by the matrix above
		assert_eq(
			harness.current_route()["route"],
			String(route_id),
			"current_route() reports '%s' after navigating there" % route_id
		)


func test_a_screen_that_is_only_instantiated_is_not_the_live_screen() -> void:
	# The exact shape of the proof this suite replaced: instantiate a brand new copy
	# of a screen, push it, and claim the screen is reachable. It is only reachable
	# if the app's own route mounted it, so this must fail for a fresh instance.
	if not _seam_is_live():
		return
	var harness := SeamHarness.live
	var scene_path := "res://src/ui/screens/socket_forge.tscn"
	var forge_route := SeamHarness.route_for_scene(scene_path)
	var moved := harness.navigate(forge_route)
	assert_eq(moved["ok"], true, "the forge route exists: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var mounted := harness.live_screen()
	var fresh := (load(scene_path) as PackedScene).instantiate()
	assert_eq(
		harness.stack.current() == fresh,
		false,
		"a freshly instantiated screen is not what the stack is showing"
	)
	assert_eq(mounted == fresh, false, "the live screen is the mounted one, not a fresh copy")
	assert_eq(
		mounted.get_instance_id(),
		harness.mounted(scene_path).get_instance_id(),
		"the harness resolves the same mounted node the stack is showing"
	)
	fresh.free()


func test_a_screen_the_app_mounted_but_detached_is_not_reachable() -> void:
	# `_mount_stack` used to push the socket forge, push the loot encounter, then pop
	# it: alive, parented to nothing a player can see, and unreachable. `detached` is
	# the harness's read of exactly that shape.
	var harness := _boot()
	if harness.boot_error != "":
		return
	for node in harness.detached:
		assert_eq(
			harness.app.is_ancestor_of(node),
			false,
			"the app created %s and then detached it, so no route reaches it" % node.name
		)
		assert_eq(
			is_instance_valid(node),
			true,
			"a detached screen is still alive but mounted under nothing reachable"
		)


func test_every_screen_the_app_builds_is_left_mounted() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	assert_eq(
		harness.detached.size(),
		0,
		"the app built screens it then detached: %s" % _names(harness.detached)
	)


# --- Every route is a player action ----------------------------------------


func test_no_public_door_into_the_stack_is_reachable_only_by_a_test() -> void:
	# BL-0121's general form. `open_screen(scene_path)` had no caller anywhere in
	# `src/`, which made the one reachability test the sole consumer of a route no
	# player could take. Any public method that opens a screen has the same shape, so
	# it has to have a caller in the shipped program or not be public.
	var body := _read(APP_SCRIPT)
	assert_eq(body.is_empty(), false, "the composition root's script is readable")
	var program := _program_text()
	for method in _public_methods(APP_SCRIPT):
		if not _is_door(method):
			continue
		var callers := 0
		for text in program:
			if text.contains("%s(" % method):
				callers += 1
		assert_eq(
			callers > 0,
			true,
			(
				(
					"%s is public and opens a screen, but nothing in src/ or scenes/ calls %s(); "
					% [APP_SCRIPT, method]
				)
				+ "it is a route only a test can use (BL-0121)"
			)
		)


## A nav bar that RENDERS sixteen buttons is not a route until a press on one moves
## the game. Asserting the bar's signal is connected proves the wiring exists; only a
## press proves a player can take it. The rest of this file reaches routes by calling
## `navigate_to` directly, which is a real door but not a *user action* — so the
## button-to-screen half of "reachable by a concrete user action" was unproven.
##
## Slot N is bound to route N by `NavBar._publish_routes`, so slot 1 is a destination
## the game does not boot on. Proving a move needs somewhere to move to.
func test_pressing_a_nav_button_moves_the_game_to_that_routes_screen() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var nav := harness.app.get_node_or_null("%NavBar")
	assert_ne(nav, null, "the mounted app carries the nav bar it composes")
	if nav == null:
		return
	var listed: Array = harness.routes().get("routes", [])
	assert_ne(
		listed.size() > 1, false, "the route table holds a destination besides the home route"
	)
	if listed.size() < 2:
		return

	var target: Dictionary = listed[1]
	var target_id := StringName(target.get("id", ""))
	var target_scene := String(target.get("scene", ""))
	assert_ne(target_id, &"", "route slot 1 names a destination")
	assert_ne(target_scene, "", "and names the scene it opens")
	var booted_at := String(harness.current_route().get("route", ""))
	assert_ne(booted_at, String(target_id), "the game does not boot on the route this button opens")

	# THE PRESS. A real Button, its real signal, the real handler, the real stack.
	# The button's name comes from the bar's own binding helper, so the test states
	# "slot 1" and lets the bar say which node that is. `press` refuses a disabled
	# control rather than counting it as success, so this also fails if the bar
	# renders the button greyed out.
	var slot_one := NavBar.slot_unique_name(1)
	assert_eq(harness.press(nav, slot_one), true, "the nav bar's slot-1 button is a live control")

	assert_eq(
		String(harness.current_route().get("route", "")),
		String(target_id),
		"pressing it moved the game to that route, so the bar is not decoration"
	)
	var mounted := harness.mounted(target_scene)
	assert_ne(mounted, null, "and the route's own screen is mounted")
	assert_eq(
		harness.live_screen(),
		mounted,
		"and it is the live screen, not merely a node somebody parented"
	)

	# The bar tracks where it sent you. A hub that navigates but never repaints is
	# the same "present but not wired out" shape this whole suite exists to catch.
	var nav_summary: Dictionary = nav.call(&"summary")
	assert_eq(
		String(nav_summary.get("active", "")),
		String(target_id),
		"the bar marks the pressed route active, so it reports where the game is"
	)

	# The one thing a hub must NOT do: pressing the same destination twice must not
	# stack a second copy. This is the double-push that `ScreenStack.push` reports,
	# reached here through a real button rather than through a test's own call.
	var depth := int((harness.app.call(&"summary") as Dictionary).get("stack", {}).get("depth", 0))
	assert_eq(harness.press(nav, slot_one), true, "the button is still live on the route it opened")
	assert_eq(
		int((harness.app.call(&"summary") as Dictionary).get("stack", {}).get("depth", 0)),
		depth,
		"pressing the route you are already on leaves the stack exactly one deep"
	)


func _is_door(method_name: String) -> bool:
	for prefix in DOOR_PREFIXES:
		if method_name.begins_with(prefix):
			return true
	return false


func _public_methods(path: String) -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load(path)
	if script == null:
		return out
	for method in script.get_script_method_list():
		var method_name := String(method.name)
		if method_name.begins_with("_"):
			continue
		out.append(method_name)
	out.sort()
	return out


func _program_text() -> Array[String]:
	var out: Array[String] = []
	for root in PROGRAM_ROOTS:
		out.append_array(_source_texts(root))
	return out


func _source_texts(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_source_texts(path))
		elif SUFFIXES.has(entry.get_extension()):
			out.append(_read(path))
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _names(nodes: Array[Node]) -> String:
	var out: Array[String] = []
	for node in nodes:
		out.append(String(node.name))
	return ", ".join(out)
