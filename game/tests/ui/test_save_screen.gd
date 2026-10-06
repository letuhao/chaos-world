extends TestCase

## THE SAVE MENU IS REACHABLE AND WIRED (ADR 0903).
##
## Four journeys with load and erase verbs, all arriving as Callables off the
## composition root because `ui/` may not name the `save` module. Every case
## drives the shipped scene and asserts the OUTCOME of a verb — a screen that
## rendered rows and moved nothing would pass a widget assertion and nothing
## else here.

const SCENE := "res://src/ui/screens/save_screen.tscn"
const ROUTE := &"save"

var _born: Array = []
var _rows: Array = []
var _loaded := ""
var _erased := ""


func setup() -> void:
	_born.clear()
	_rows.clear()
	_loaded = ""
	_erased = ""


## Everything this suite minted, freed. Bare instantiations only (AGENTS.md).
func teardown() -> void:
	for node in _born:
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	_rows.clear()


func _screen() -> SaveScreen:
	var packed := load(SCENE) as PackedScene
	var screen := packed.instantiate() as SaveScreen
	_born.append(screen)
	return screen


func _wired(screen: SaveScreen) -> void:
	screen.bind_save(
		Callable(self, "_stub_list"), Callable(self, "_stub_load"), Callable(self, "_stub_erase")
	)


func _stub_list() -> Array:
	return _rows.duplicate(true)


func _stub_load(slot: StringName) -> Dictionary:
	_loaded = String(slot)
	return {"ok": true, "reason": "", "slot": _loaded}


func _stub_erase(slot: StringName) -> Dictionary:
	_erased = String(slot)
	return {"ok": true, "reason": "", "slot": _erased, "erased": true}


func _row(slot: String, exists: bool) -> Dictionary:
	return {
		"slot": slot,
		"title": slot,
		"exists": exists,
		"generation": 3 if exists else 0,
		"difficulty": "standard" if exists else "",
		"actor_id": "hero" if exists else "",
		"display_name": "Hero" if exists else "",
		"is_live": slot == "primary",
	}


# --- The route ---------------------------------------------------------------


func test_the_route_table_names_the_save_page_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "saves is a named route")
	assert_eq(String(ScreenRoutes.key_of(ROUTE)), "w", "and its key is w")


func test_the_save_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_w", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


# --- The seams -----------------------------------------------------------------


func test_a_screen_with_no_actor_reports_nothing() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "saves bound to nobody is {}, not a page of rows")


func test_verbs_refuse_by_name_when_no_seam_is_bound() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	assert_eq(String(screen.act_load(&"first").get("reason", "")), "no_load_seam", "load names it")
	assert_eq(
		String(screen.act_erase(&"first").get("reason", "")), "no_erase_seam", "erase names it"
	)


func test_rows_mirror_the_list_seam_and_verbs_go_through_it() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_rows = [
		_row("primary", true), _row("first", true), _row("second", false), _row("third", false)
	]
	_wired(screen)
	var view := screen.summary()
	assert_eq(
		view.get("slot_ids", []) as Array,
		["primary", "first", "second", "third"],
		"all four journeys are rows"
	)
	assert_eq(
		screen.act_load(&"first"),
		{"ok": true, "reason": "", "slot": "first"},
		"load hands the verdict back"
	)
	assert_eq(_loaded, "first", "through the seam with the row's own id")
	assert_eq(
		screen.act_erase(&"second"),
		{"ok": true, "reason": "", "slot": "second", "erased": true},
		"and so does erase"
	)
	assert_eq(_erased, "second", "through the same seam")


func test_an_empty_row_offers_nothing_to_press() -> void:
	var screen := _screen()
	screen.setup(Actor.new())
	_rows = [
		_row("primary", false), _row("first", false), _row("second", false), _row("third", false)
	]
	_wired(screen)
	var rows := screen.summary().get("slots", []) as Array
	assert_eq(rows.size(), 4, "all four rows still render")
	for row in rows:
		assert_eq(bool((row as Dictionary).get("can_load", true)), false, "and none of them loads")
