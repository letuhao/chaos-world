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


func setup() -> void:
	_born.clear()
	_save_exists = false
	_continued = false
	_new_game_verdict = {}


## Everything this suite minted, freed. The stack frees its own screens, so
## only bare instantiations need releasing; a suite that leaves one parented
## leaks a subtree per case, which is the 67 GB incident AGENTS.md records.
func teardown() -> void:
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
		Callable(self, "_stub_new_game")
	)


func _stub_has_save() -> bool:
	return _save_exists


func _stub_continue() -> bool:
	_continued = true
	return true


func _stub_new_game() -> Dictionary:
	_new_game_verdict = {"ok": true, "reason": ""}
	return _new_game_verdict.duplicate(true)


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
	assert_eq(bool(view.get("can_new_game", false)), true, "and so is New Game")
