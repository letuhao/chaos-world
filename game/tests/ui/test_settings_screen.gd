extends TestCase

## THE SETTINGS SCREEN IS REACHABLE AND WIRED (menu slice).
##
## `DifficultyApi.views()` publishes preset rows "for a settings screen" and
## had no settings screen; the setter had no caller outside the hearth half.
## Every case drives the shipped scene and asserts the OUTCOME of a verb — a
## screen that rendered rows and selected nothing would pass a widget
## assertion and nothing else here.

const SCENE := "res://src/ui/screens/settings_screen.tscn"
const ROUTE := &"settings"

var _born: Array = []
var _selected := ""


func setup() -> void:
	_born.clear()
	_selected = ""


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


func _screen() -> SettingsScreen:
	var packed := load(SCENE) as PackedScene
	var screen := packed.instantiate() as SettingsScreen
	_born.append(screen)
	return screen


func _stub_select(difficulty_id: StringName) -> Dictionary:
	_selected = String(difficulty_id)
	return {"ok": true, "reason": "", "difficulty_id": _selected}


# --- The route ---------------------------------------------------------------


func test_the_route_table_names_the_settings_page_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "settings is a named route")
	assert_eq(String(ScreenRoutes.key_of(ROUTE)), "u", "and its key is u")


func test_the_settings_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_u", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


# --- The seam -----------------------------------------------------------------


func test_a_screen_with_no_actor_reports_nothing() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "settings bound to nobody is {}, not a page of zeroes")


func test_select_refuses_by_name_when_no_seam_is_bound() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	var verdict := screen.act_select(&"hard")
	assert_eq(bool(verdict.get("ok", true)), false, "no seam, no selection")
	assert_eq(String(verdict.get("reason", "")), "no_select_seam", "and it names the seam")


func test_selecting_a_preset_goes_through_the_module_verdict() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	screen.bind_difficulty(Callable(self, "_stub_select"))
	var verdict := screen.act_select(&"hard")
	assert_eq(bool(verdict.get("ok", false)), true, "the press runs")
	assert_eq(_selected, "hard", "through the seam with the row's own id")
	assert_eq(
		String(screen.summary().get("current_id", "")),
		String(DifficultyApi.current_id(screen.actor())),
		"and the page reads the run's own difficulty back, not its memory of the press"
	)


func test_the_summary_names_every_preset_the_module_publishes() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	screen.bind_difficulty(Callable(self, "_stub_select"))
	var view := screen.summary()
	var shown := view.get("preset_ids", []) as Array
	assert_eq(shown.size(), int(view.get("total_presets", -1)), "every published preset is a row")
	assert_eq(bool(view.get("difficulty_seam", false)), true, "and the seam is reported")
