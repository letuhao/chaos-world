extends TestCase

## THE MAIN MENU IS REACHABLE AND WIRED (boot slice).
##
## Boot used to be a silent decision: a restored body went to the workbench, a
## fresh boot went to arrival, and a player who wanted the other door had no
## door. This suite pins the door — the route, its key, its action, and the
## three seams the screen is made of — driven the way a player drives it.
##
## Every case instantiates the shipped scene and asserts the OUTCOME of a verb,
## never widget existence. A screen that rendered two buttons and moved nothing
## would pass a "the button is enabled" assertion and nothing else here.

const SCENE := "res://src/ui/screens/boot_screen.tscn"
const ROUTE := &"boot"

var _born: Array = []
var _save_exists := false
var _continued := false
var _new_game_verdict := {}
var _opened: Array = []
var _quit_called := false


func setup() -> void:
	_born.clear()
	_save_exists = false
	_continued = false
	_new_game_verdict = {}
	_opened.clear()
	_quit_called = false


## Everything this suite minted, freed. The stack frees its own screens, so
## only bare instantiations need releasing; a suite that leaves one parented
## leaks a subtree per case, which is the 67 GB incident AGENTS.md records.
func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	for node in _born:
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()


func _screen() -> BootScreen:
	var packed := load(SCENE) as PackedScene
	var screen := packed.instantiate() as BootScreen
	_born.append(screen)
	return screen


func _wired(screen: BootScreen) -> void:
	screen.bind_menu(
		Callable(self, "_stub_has_save"),
		Callable(self, "_stub_continue"),
		Callable(self, "_stub_new_game"),
		Callable(self, "_stub_open"),
		Callable(self, "_stub_quit")
	)


func _stub_has_save() -> bool:
	return _save_exists


func _stub_continue() -> bool:
	_continued = true
	return true


func _stub_new_game() -> Dictionary:
	_new_game_verdict = {"ok": true, "reason": ""}
	return _new_game_verdict.duplicate(true)


func _stub_open(route_id: StringName) -> bool:
	_opened.append(String(route_id))
	return true


func _stub_quit() -> Dictionary:
	_quit_called = true
	return {"ok": true, "reason": ""}


# --- The route ---------------------------------------------------------------


func test_the_route_table_names_the_menu_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "the menu is a named route")
	assert_eq(String(ScreenRoutes.key_of(ROUTE)), "o", "and its key is o")


func test_the_menus_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_o", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


# --- The seams ----------------------------------------------------------------


func test_a_screen_with_no_actor_reports_nothing() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "a menu bound to nobody is {}, not a menu of zeroes")


func test_verbs_refuse_by_name_when_no_seam_is_bound() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	assert_eq(screen.act_continue(), false, "Continue with no seam goes nowhere")
	assert_eq(
		String(screen.act_new_game().get("reason", "")),
		"no_new_game_seam",
		"and New Game names the missing seam rather than calling into a void Callable"
	)


func test_continue_is_offered_only_when_a_save_exists() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_wired(screen)
	_save_exists = false
	assert_eq(screen.can_continue(), false, "no save, no Continue")
	assert_eq(screen.act_continue(), false, "and pressing it goes nowhere")
	_save_exists = true
	assert_eq(screen.can_continue(), true, "a save means Continue")
	assert_eq(screen.act_continue(), true, "and pressing it moves")
	assert_eq(_continued, true, "through the root's own movement seam")


func test_new_game_hands_the_arrival_verdict_back_verbatim() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_wired(screen)
	var verdict := screen.act_new_game()
	assert_eq(bool(verdict.get("ok", false)), true, "New Game opens arrival")
	assert_eq(_new_game_verdict.get("ok", false), true, "through the seam, not around it")


func test_the_summary_names_what_the_player_can_do() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_wired(screen)
	_save_exists = true
	var view := screen.summary()
	assert_eq(bool(view.get("has_save", false)), true, "a save is reported")
	assert_eq(bool(view.get("can_continue", false)), true, "Continue is reported")
	assert_eq(bool(view.get("can_new_game", false)), true, "New Game is reported")
	assert_eq(bool(view.get("can_open", false)), true, "and so are the menu pages")
	assert_eq(bool(view.get("can_quit", false)), true, "and Quit")


func test_menu_pages_open_through_the_roots_own_door() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_wired(screen)
	assert_eq(screen.act_open(&"settings"), true, "Settings opens")
	assert_eq(screen.act_open(&"credits"), true, "Credits opens")
	assert_eq(_opened, ["settings", "credits"], "through the seam, not around it")


func test_menu_pages_refuse_by_name_when_no_seam_is_bound() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	assert_eq(screen.act_open(&"settings"), false, "no seam, no journey")
	assert_eq(screen.act_quit().get("reason", ""), "no_quit_seam", "and Quit names it too")


func test_quit_goes_through_the_root_which_owns_the_tree() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_wired(screen)
	var verdict := screen.act_quit()
	assert_eq(bool(verdict.get("ok", false)), true, "Quit is handed over")
	assert_eq(_quit_called, true, "to the root, which is the only layer that may end the process")


func test_the_nav_bar_hides_while_the_menu_owns_the_screen() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	var harness := SeamHarness.mount_new()
	if String(harness.boot_error) != "":
		assert_eq(String(harness.boot_error), "", "the shell booted")
		return
	var nav := harness.app.get_node_or_null("%NavBar") as Control
	assert_ne(nav, null, "the mounted shell carries its nav bar")
	if nav == null:
		return
	assert_eq(nav.visible, true, "the bar is up on the arrival route the boot opens")
	assert_eq(bool(harness.navigate(&"boot").get("ok", false)), true, "the menu opens")
	assert_eq(nav.visible, false, "and the bar hides behind it")
	assert_eq(bool(harness.navigate(&"workbench").get("ok", false)), true, "going home works")
	assert_eq(nav.visible, true, "and the bar comes back with the game")
	harness.teardown()
