extends TestCase

## The channel list and the condition line (ADR 0043 gap audit).
##
## Twenty meridian channels with state, refinement and injury are the richest
## player-visible state in the game. They used to reach the screen as a single
## comma-joined Label, so a player could not see which channel blocked a gate.
## These lock the per-channel rendering and the unmet-conditions line.

const LIST := "res://src/ui/panels/channel_list.tscn"
const QI_SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"
const MIND_SCREEN := "res://src/ui/screens/mind_cultivation_screen.tscn"


func _list() -> ChannelList:
	return (load(LIST) as PackedScene).instantiate() as ChannelList


func _qi() -> QiCultivationScreen:
	return (load(QI_SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _mind() -> MindCultivationScreen:
	return (load(MIND_SCREEN) as PackedScene).instantiate() as MindCultivationScreen


func _entries() -> Array:
	return [
		{"id": "lung", "name": "Lung", "state": "open", "refinement": 1, "injured": false},
		{
			"id": "spleen",
			"name": "Spleen",
			"state": "closed",
			"refinement": 0,
			"injured": false,
		},
		{
			"id": "heart",
			"name": "Heart",
			"state": "expanded",
			"refinement": 2,
			"injured": true,
		},
	]


func _qi_actor() -> Actor:
	var actor := Actor.new(&"ch_qi", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(actor, 512)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	return actor


func _mind_actor() -> Actor:
	var actor := Actor.new(&"ch_mind", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(actor, 512)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	return actor


# --- The list --------------------------------------------------------------


func test_summary_is_empty_without_state() -> void:
	var list := _list()
	assert_eq(list.summary().get("channels", []).size(), 0, "no entries, no rows")
	list.free()


func test_it_renders_one_row_per_required_channel() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung", "spleen"]})
	var view := list.summary()
	assert_eq(view.get("required_count", 0), 2, "two channels are required")
	assert_eq(view.get("row_count", 0), 3, "required channels plus the injured one")
	list.free()


func test_an_injured_channel_is_shown_even_when_not_required() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung"]})
	var ids := list.visible_ids()
	assert_eq(ids.has("heart"), true, "an injury is actionable, so it is never hidden")
	assert_eq(ids.has("spleen"), false, "a closed, unrequired, healthy channel stays quiet")
	list.free()


func test_a_channel_row_carries_state_refinement_and_the_required_flag() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung"]})
	var rows: Array = list.summary().get("channels", [])
	var lung: Dictionary = rows[0]
	assert_eq(lung.get("id", ""), "lung", "id")
	assert_eq(lung.get("state", ""), "open", "state is a field, not baked into a string")
	assert_eq(lung.get("refinement", -1), 1, "refinement depth is exposed")
	assert_eq(lung.get("required", false), true, "the gate flag is exposed")
	assert_eq(lung.get("text", ""), "Lung open d1 (required)", "the row renders one line")
	list.free()


func test_an_injured_channel_is_marked_in_its_row() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung"], "show_all": true})
	for row in list.summary().get("channels", []):
		if row.get("id", "") == "heart":
			assert_eq(row.get("text", ""), "Heart expanded d2 INJURED", "injury is visible")
	list.free()


func test_show_all_lists_every_channel() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung"], "show_all": true})
	assert_eq(list.visible_ids().size(), 3, "every channel is on screen")
	list.free()


func test_least_developed_required_channel_sorts_first() -> void:
	var list := _list()
	list.set_state({"channels": _entries(), "required": ["lung", "spleen"]})
	# Spleen is closed and Lung is open, so the channel with work left leads.
	assert_eq(
		list.summary().get("channels", [])[0].get("id", ""), "spleen", "closed sorts ahead of open"
	)
	list.free()


# --- The condition line ----------------------------------------------------


func test_the_qi_screen_renders_its_unmet_conditions() -> void:
	var screen := _qi()
	screen.setup(_qi_actor())
	var unmet: Array = screen.summary().get("unmet", [])
	assert_ne(unmet.size(), 0, "the gate is not met yet")
	var label := screen.get_node_or_null("%ConditionLabel") as Label
	assert_ne(label, null, "the screen has a condition line")
	assert_ne(label.text, "", "the line is written, not left blank")
	assert_eq(label.text.begins_with("Conditions:"), true, "it says what it is")
	assert_ne(label.text.find("Conditions:"), -1, "prefix")
	# The specific blocker must be visible to the player.
	assert_eq(label.text.find("channel_not_ready") >= 0, true, "the blocker is named")
	screen.free()


func test_the_qi_condition_line_names_the_required_item() -> void:
	var screen := _qi()
	screen.setup(_qi_actor())
	var label := screen.get_node_or_null("%ConditionLabel") as Label
	var costs: Dictionary = screen.summary().get("costs", {})
	assert_ne(costs.size(), 0, "the gate names the pill it wants")
	for key in costs:
		assert_ne(
			label.text.find(String(key)), -1, "the pill id is shown, not just 'a pill is missing'"
		)
	screen.free()


func test_the_mind_screen_renders_its_unmet_conditions() -> void:
	var screen := _mind()
	screen.setup(_mind_actor())
	var label := screen.get_node_or_null("%ConditionLabel") as Label
	assert_ne(label, null, "the screen has a condition line")
	assert_ne(label.text, "", "the mind path explains itself too")
	screen.free()


func test_turbulence_gets_a_row() -> void:
	var screen := _mind()
	screen.setup(_mind_actor())
	var vitals: Dictionary = screen.summary().get("vitals", {})
	assert_eq(vitals.has("turbulence"), true, "turbulence is rendered, not just summarized")
	list_free(screen)


func test_the_realm_line_is_written_not_left_as_a_placeholder() -> void:
	var screen := _qi()
	screen.setup(_qi_actor())
	var label := screen.get_node_or_null("%RealmLabel") as Label
	assert_ne(label, null, "the screen declares a realm line")
	assert_ne(label.text.find("qi_refining"), -1, "the current realm is shown")
	list_free(screen)


func list_free(_screen: Node) -> void:
	_screen.free()
