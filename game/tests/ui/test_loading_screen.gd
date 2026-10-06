extends TestCase

## THE LOADING SCREEN OWNS THE BOOT WINDOW (ADR 0901).
##
## Wallpaper, weather, honest progress: every route scene loads up front, one
## per `load_step()`, so the bar fills from work really done. Every case
## drives the shipped scene and asserts the OUTCOME of a verb — a screen that
## rendered a bar and loaded nothing would pass a widget assertion and nothing
## else here.

const SCENE := "res://src/ui/screens/loading_screen.tscn"
const ROUTE := &"loading"

var _born: Array = []


func setup() -> void:
	_born.clear()


## Everything this suite minted, freed. Bare instantiations only; a suite that
## leaves one parented leaks a subtree per case (AGENTS.md, the 67 GB run).
func teardown() -> void:
	for node in _born:
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()


func _screen() -> LoadingScreen:
	var packed := load(SCENE) as PackedScene
	var screen := packed.instantiate() as LoadingScreen
	_born.append(screen)
	return screen


# --- The route ---------------------------------------------------------------


func test_the_route_table_names_the_loading_screen_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "loading is a named route")
	assert_eq(String(ScreenRoutes.key_of(ROUTE)), "z", "and its key is z")


func test_the_loading_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_z", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


# --- The walk -----------------------------------------------------------------


func test_a_screen_with_no_actor_reports_nothing() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "loading bound to nobody is {}, not a bar of zeroes")


func test_steps_refuse_before_the_walk_begins() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	var step := screen.load_step()
	assert_eq(bool(step.get("ok", true)), false, "no step runs before begin_load")
	assert_eq(String(step.get("reason", "")), "no_load_started", "and it names why")


func test_the_walk_loads_every_route_scene_and_then_reports_done() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	var scenes: Array = []
	for row in ScreenRoutes.all():
		var path := String(row.get("scene", ""))
		if not path.is_empty():
			scenes.append(path)
	var begun := screen.begin_load(scenes)
	var total := int(begun.get("total", 0))
	assert_eq(total > 0, true, "there are route scenes to walk, so the loop below is real")
	var step := {}
	# Bounded by the route count the walk itself reported: each step loads
	# exactly one scene, so the walk cannot outrun its own denominator.
	for i in total:
		step = screen.load_step()
		if bool(step.get("done", false)):
			break
	assert_eq(bool(step.get("done", false)), true, "the walk finishes")
	assert_eq(int(step.get("loaded", -1)), total, "having loaded every scene")
	var view := screen.summary()
	assert_eq(bool(view.get("done", false)), true, "and the summary says so too")


func test_missing_art_degrades_plate_by_plate() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	assert_eq(
		screen.set_backdrop("res://assets/loading/no_such_file.png"), false, "no file, no hang"
	)
	var hung := screen.set_layers(
		"res://assets/loading/no_such_file.png",
		"res://assets/loading/no_such_file.png",
		"res://assets/loading/no_such_file.png"
	)
	assert_eq(hung, 0, "nothing hung, and nothing crashed")
