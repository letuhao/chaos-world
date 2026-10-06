extends TestCase

## THE CREDITS SCREEN IS REACHABLE AND MIRRORS ITS SCENE (menu slice).
##
## Credits are static authored lines with no module behind them, so the one
## failure shape is drift: a line edited in the scene but not in the script's
## mirror, or the reverse. Every case below pins the mirror from both sides.

const SCENE := "res://src/ui/screens/credits_screen.tscn"
const ROUTE := &"credits"

var _born: Array = []


func setup() -> void:
	_born.clear()


## Everything this suite minted, freed. Bare instantiations only (AGENTS.md).
func teardown() -> void:
	for node in _born:
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()


func _screen() -> CreditsScreen:
	var packed := load(SCENE) as PackedScene
	var screen := packed.instantiate() as CreditsScreen
	_born.append(screen)
	return screen


# --- The route ---------------------------------------------------------------


func test_the_route_table_names_the_credits_page_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "credits is a named route")
	assert_eq(String(ScreenRoutes.key_of(ROUTE)), "x", "and its key is x")


func test_the_credits_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_x", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


# --- The mirror ---------------------------------------------------------------


func test_a_screen_with_no_actor_reports_nothing() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "credits bound to nobody is {}, not a page of lines")


func test_every_credited_line_reaches_the_summary() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	var view := screen.summary()
	var lines := view.get("lines", []) as Array
	assert_eq(lines.size(), int(view.get("line_count", -1)), "the count counts the lines")
	assert_eq(lines.size() > 0, true, "and there are lines to read")
	assert_eq(lines.has("Built with Godot 4.7."), true, "including the engine credit")
