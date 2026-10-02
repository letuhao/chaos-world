extends TestCase

## The set/unique screen and its panels are pure renderers of the snapshot the
## `set_bonus` facade publishes. These assert `summary()` with no scene tree,
## which is the same contract the headless CLI reads (ADR 0030/0038/0042).

const SCREEN_SCENE := "res://src/ui/screens/set_bonus_screen.tscn"
const ROW_SCENE := "res://src/ui/panels/set_threshold_row.tscn"
const PANEL_SCENE := "res://src/ui/panels/set_bonus_panel.tscn"
const SET_ID := &"ironhide_vigil"
const BAND := "set_ironhide_vigil_band"
const PLATE := "set_ironhide_vigil_wardplate"
const BLADE := "set_ironhide_vigil_greatblade"


func _hero() -> Actor:
	var actor := Actor.new(&"reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor, 48)
	SetBonusApi.attach(actor)
	return actor


func _wear(actor: Actor, slot: StringName, def_id: String) -> void:
	var def := SetBonusApi.definition(StringName(def_id))
	ItemsApi.inventory(actor).add(def, 1)
	ItemsApi.equip_item(actor, slot, def)


func _screen() -> SetBonusScreen:
	return (load(SCREEN_SCENE) as PackedScene).instantiate() as SetBonusScreen


## An action event rather than a key event, so the test drives the screen's
## action vocabulary directly and does not depend on the project's key bindings.
func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- The screen contract ---------------------------------------------------


func test_the_screen_is_empty_without_an_actor_or_a_snapshot() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "nothing to show before it is bound")
	screen.setup(_hero())
	assert_eq(screen.summary(), {}, "an actor alone is not a snapshot")
	screen.apply_snapshot(SetBonusApi.inspect(_hero()))
	assert_eq(screen.summary().is_empty(), false, "a snapshot gives a view")
	screen.free()


func test_the_screen_nests_the_panel_summary_under_its_own_key() -> void:
	var screen := _screen()
	var actor := _hero()
	screen.setup(actor)
	screen.apply_snapshot(SetBonusApi.inspect(actor))
	var view := screen.summary()
	assert_eq(int(view["set_count"]), SetBonusApi.sets().size(), "every set is offered")
	# The screen opens on the catalog's first set, so the order is the catalog's
	# to own and the screen never invents one.
	assert_eq(String(view["selected_set"]), String((view["available_sets"] as Array)[0]), "a set")
	assert_eq(int(view["unique_total"]) >= 4, true, "the uniques are counted")
	var panel: Dictionary = view["panel"]
	assert_eq(not panel.is_empty(), true, "the panel summary is nested")
	assert_eq(String(panel["set_id"]), String(view["selected_set"]), "and names the same set")
	assert_eq(int(view["active_threshold_count"]), 0, "nothing is worn yet")
	screen.free()


func test_the_screen_selects_a_named_set() -> void:
	var screen := _screen()
	screen.setup(_hero())
	screen.apply_snapshot(SetBonusApi.inspect(_hero()))
	assert_eq(screen.select_set(String(SET_ID)), true, "a named set can be selected")
	assert_eq(screen.selected_set(), String(SET_ID), "and is shown")
	assert_eq(screen.select_set("no_such_set"), false, "an unknown set is refused")
	assert_eq(screen.selected_set(), String(SET_ID), "and the shown set does not change")
	screen.free()


func test_the_screen_reports_active_thresholds_from_the_worn_members() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	_wear(actor, &"weapon", BLADE)
	var screen := _screen()
	screen.setup(actor)
	screen.apply_snapshot(SetBonusApi.inspect(actor))
	screen.select_set(String(SET_ID))
	var view := screen.summary()
	assert_eq(String(view["selected_set"]), String(SET_ID), "the worn set is shown")
	assert_eq(int(view["active_threshold_count"]), 2, "two thresholds are active")
	assert_eq(view["active_sets"] as Array, [String(SET_ID)], "and the set reports active")
	var panel: Dictionary = view["panel"]
	assert_eq(int(panel["equipped_count"]), 3, "three members worn")
	assert_eq((panel["member_lines"] as Array).size(), 5, "every member is listed")
	assert_eq(int(panel["threshold_count"]), 4, "every threshold is listed")
	screen.free()


func test_summary_keys_and_values_are_primitives() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	var screen := _screen()
	screen.setup(actor)
	screen.apply_snapshot(SetBonusApi.inspect(actor))
	var view := screen.summary()
	for key in view.keys():
		assert_eq(typeof(key) == TYPE_STRING, true, "screen key %s is a string" % key)
		if key == "panel":
			continue
		assert_eq(_primitive(view[key]), true, "screen value %s is primitive" % key)
	var panel: Dictionary = view["panel"]
	for threshold in panel["thresholds"]:
		var row: Dictionary = threshold
		for key in row.keys():
			assert_eq(typeof(key) == TYPE_STRING, true, "row key %s is a string" % key)
			if key == "options":
				continue
			assert_eq(_primitive(row[key]), true, "row value %s is primitive" % key)
	screen.free()


func _primitive(value) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_ARRAY:
			for entry in value:
				if not _primitive(entry):
					return false
			return true
		_:
			return false


# --- Screen stack hooks ----------------------------------------------------


func test_the_stack_hooks_exist_and_are_safe_with_nothing_bound() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "still empty")
	assert_eq(screen.on_stack_input(null), false, "a null event is declined")
	screen.free()


func test_the_screen_cycles_sets_with_left_and_right_and_declines_everything_else() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	screen.apply_snapshot(SetBonusApi.inspect(actor))
	var ids: Array = screen.summary()["available_sets"]
	assert_eq(ids.size() >= 2, true, "there is more than one set to cycle")
	assert_eq(screen.on_stack_input(_press(&"ui_right")), true, "right moves to the next set")
	assert_eq(screen.selected_set(), String(ids[1]), "the next set is shown")
	assert_eq(screen.on_stack_input(_press(&"ui_left")), true, "left moves back")
	assert_eq(screen.selected_set(), String(ids[0]), "the first set is shown again")
	assert_eq(
		screen.on_stack_input(_press(&"ui_cancel")), false, "cancel is declined so the stack pops"
	)
	assert_eq(
		screen.on_stack_input(_press(&"ui_focus_next")), false, "an unrelated action is declined"
	)
	screen.free()


func test_the_screen_records_focus_without_a_viewport() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	screen.apply_snapshot(SetBonusApi.inspect(actor))
	screen.focus_initial()
	assert_eq(
		String(screen.summary()["panel"]["thresholds"][0]["focus_target"]),
		"SetThresholdRow",
		"focus lands on the first threshold row"
	)
	screen.free()


# --- The threshold row owns the formatting ----------------------------------


func test_the_threshold_row_owns_every_number_format() -> void:
	var row := (load(ROW_SCENE) as PackedScene).instantiate() as SetThresholdRow
	assert_eq(row.summary(), {}, "empty with no threshold")
	(
		row
		. show_threshold(
			{
				"index": 0,
				"count": 2,
				"label": "Vigil Pair",
				"active": true,
				"source": "set:ironhide_vigil:0",
				"options":
				[
					{
						"option_id": "core_defense_physical",
						"label": "Defense",
						"unit": "magnitude",
						"target_id": "defense_physical",
						"value": 6.0,
						"value_min": 1.8,
						"value_max": 18.0,
					},
					{
						"option_id": "core_max_health",
						"label": "Max Health",
						"unit": "magnitude",
						"target_id": "max_health",
						"value": 12.0,
						"value_min": 1.8,
						"value_max": 18.0,
					},
				],
			}
		)
	)
	var view := row.summary()
	assert_eq(bool(view["active"]), true, "the active state is reported")
	assert_eq(int(view["count"]), 2, "the authored count is reported")
	assert_eq(String(view["source"]), "set:ironhide_vigil:0", "the source id is reported")
	assert_ne(String(view["headline"]).find("Vigil Pair"), -1, "the label is readable")
	assert_ne(String(view["headline"]).find("2"), -1, "the count is formatted by the row")
	assert_ne(String(view["effect_line"]).find("6.00"), -1, "the granted value is formatted")
	assert_ne(String(view["effect_line"]).find("1.80 - 18.00"), -1, "its window is shown")
	assert_ne(String(view["state_line"]).find("ACTIVE"), -1, "the state line says so")
	assert_eq(String(view["tone"]), "OkLabel", "an active threshold is toned as such")
	assert_eq((view["options"] as Array).size(), 2, "raw option values are still exposed")
	assert_almost_eq(float((view["options"] as Array)[0]["value"]), 6.0, "raw, not a string")
	row.free()


func test_an_inactive_threshold_says_what_it_is_waiting_for() -> void:
	var row := (load(ROW_SCENE) as PackedScene).instantiate() as SetThresholdRow
	(
		row
		. show_threshold(
			{
				"index": 3,
				"count": 5,
				"label": "Vigil Complete",
				"active": false,
				"source": "set:ironhide_vigil:3",
				"options": [],
			}
		)
	)
	var view := row.summary()
	assert_eq(bool(view["active"]), false, "not active")
	assert_ne(String(view["state_line"]).find("needs 5"), -1, "it says what it waits for")
	assert_eq(String(view["tone"]), "MetaLabel", "an inactive threshold is not toned as active")
	row.free()


func test_the_panel_shows_membership_fixed_options_and_locked_signatures() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as SetBonusPanel
	panel.set_snapshot(SetBonusApi.inspect(actor))
	panel.select_set(String(SET_ID))
	var view := panel.summary()
	assert_eq(String(view["set_id"]), String(SET_ID), "the first set is shown")
	assert_eq(int(view["equipped_count"]), 2, "two members worn")
	var lines: Array = view["member_lines"]
	assert_eq(lines.size(), 5, "every member is listed")
	var worn := 0
	for line in lines:
		if String(line).find("worn in") >= 0:
			worn += 1
	assert_eq(worn, 2, "exactly the worn members say so")
	var unique_lines: Array = view["unique_lines"]
	assert_eq(unique_lines.size(), 1, "the set's unique is spelled out")
	assert_ne(String(unique_lines[0]).find("E2_nascent_soul_herald"), -1, "its route is named")
	assert_ne(String(unique_lines[0]).find("core_max_health"), -1, "its locked option is named")
	assert_ne(String(view["meta"]).find("2 of 5 members"), -1, "the panel formats the count")
	panel.free()


func test_the_panel_rejects_an_unknown_set_and_stays_on_the_one_it_shows() -> void:
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as SetBonusPanel
	panel.set_snapshot(SetBonusApi.inspect(_hero()))
	var shown := panel.selected_set()
	assert_ne(shown, "", "a set is shown")
	assert_eq(panel.select_set("no_such_set"), false, "an unknown set is refused")
	assert_eq(panel.selected_set(), shown, "and the shown set does not change")
	panel.clear()
	assert_eq(panel.summary(), {}, "clearing empties the snapshot")
	panel.free()
