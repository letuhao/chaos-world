extends TestCase

## The reusable UI foundation (ADR 0043): `StatRow` owns every number format,
## `ActionSet` owns the action row and result tone, and `UiScreen` is the screen
## base. These assert `summary()` with no scene tree, which is the same contract
## the headless CLI reads.

const ROW := "res://src/ui/panels/stat_row.tscn"
const ACTIONS := "res://src/ui/panels/action_set.tscn"
const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"


func _row() -> StatRow:
	return (load(ROW) as PackedScene).instantiate() as StatRow


func _actions() -> ActionSet:
	return (load(ACTIONS) as PackedScene).instantiate() as ActionSet


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


# --- StatRow owns the formatting -------------------------------------------


func test_stat_row_is_empty_without_state() -> void:
	var row := _row()
	assert_eq(row.summary(), {}, "no name, nothing to report")
	row.set_state({})
	assert_eq(row.summary(), {}, "an empty state stays empty")
	row.free()


func test_stat_row_owns_the_current_over_maximum_format() -> void:
	var row := _row()
	row.set_state({"name": "Qi", "current": 120.0, "maximum": 300.0})
	var view := row.summary()
	assert_eq(view.get("text", ""), "120/300", "the row formats, the screen does not")
	assert_eq(view.get("current", 0.0), 120.0, "raw value is still exposed")
	row.free()


func test_stat_row_decimals_are_opt_in() -> void:
	var row := _row()
	row.set_state({"name": "Dantian", "current": 0.5, "maximum": 1.0, "decimals": 2})
	assert_eq(row.summary().get("text", ""), "0.50/1.00", "two decimals when asked")
	row.set_state({"name": "Dantian", "current": 0.5, "maximum": 0.0, "decimals": 0})
	assert_eq(row.summary().get("text", ""), "1", "no maximum renders the bare value")
	row.free()


func test_stat_row_bar_ratio_is_clamped() -> void:
	var row := _row()
	row.set_state({"name": "Qi", "current": 50.0, "maximum": 100.0, "mode": StatRow.MODE_BAR})
	assert_eq(row.summary().get("bar_ratio", -1.0), 0.5, "half full")
	row.set_state({"current": 500.0})
	assert_eq(row.summary().get("bar_ratio", -1.0), 1.0, "over-full clamps to full")
	row.set_state({"maximum": 0.0})
	assert_eq(row.summary().get("bar_ratio", -1.0), 0.0, "no maximum is not full by accident")
	row.free()


# --- ActionSet owns the enabled-state and the tone --------------------------


func test_action_set_defaults_every_action_to_disabled() -> void:
	var actions := _actions()
	(
		actions
		. set_state(
			{
				"actions": [&"cultivate", &"breakthrough"],
				"labels": {"cultivate": "Cultivate", "breakthrough": "Breakthrough"},
				"enabled": {"cultivate": true},
			}
		)
	)
	var view := actions.summary()
	var enabled: Dictionary = view.get("enabled", {})
	assert_eq(enabled.get("cultivate", false), true, "declared live")
	assert_eq(enabled.get("breakthrough", true), false, "undeclared is never live by accident")
	assert_eq(view.get("available", []), ["cultivate"], "only live actions are offered")
	actions.free()


func test_action_set_renders_a_rejection_in_the_message_line() -> void:
	var actions := _actions()
	actions.set_state({"actions": [&"breakthrough"], "enabled": {"breakthrough": true}})
	actions.set_message("Not ready", ActionSet.TONE_ERROR)
	var view := actions.summary()
	assert_eq(view.get("message", ""), "Not ready", "the reason is visible")
	assert_eq(view.get("tone", ""), "error", "tone is reported")
	actions.set_message("")
	assert_eq(view.get("message", "x"), "Not ready", "clearing takes effect on the next read")
	actions.free()


func test_action_set_refuses_an_action_that_is_not_live() -> void:
	var actions := _actions()
	actions.set_state({"actions": [&"cultivate"], "enabled": {"cultivate": false}})
	assert_eq(actions.request(&"cultivate"), false, "a blocked action does not fire")
	assert_eq(actions.request(&"nosuch"), false, "an unknown action does not fire")
	actions.set_state({"enabled": {"cultivate": true}})
	assert_eq(actions.request(&"cultivate"), true, "a live action fires")
	actions.free()


func test_action_set_records_focus_without_a_viewport() -> void:
	var actions := _actions()
	(
		actions
		. set_state(
			{
				"actions": [&"cultivate", &"breakthrough"],
				"enabled": {"cultivate": true, "breakthrough": true},
			}
		)
	)
	actions.focus_initial()
	assert_eq(
		actions.summary().get("focus_target", ""),
		"CultivateButton",
		"first live action is the target"
	)
	actions.free()


# --- The screen base is drivable headlessly ---------------------------------


func test_screen_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not partial")
	screen.setup(Actor.new(&"bare"))
	assert_eq(screen.summary().is_empty(), true, "an actor on no path yields no view")
	screen.free()


func test_screen_reports_the_shared_key_vocabulary() -> void:
	var screen := _screen()
	var actor := Actor.new(&"vocab", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	screen.setup(actor)
	var view := screen.summary()
	for key in ["realm", "target", "progress", "can_act", "chance", "unmet", "costs"]:
		assert_eq(view.has(key), true, "%s is in the shared vocabulary" % key)
	# The facade calls it `can_attempt`; the screen normalizes so two screens
	# cannot disagree about the key.
	assert_eq(view.has("can_attempt"), false, "no facade vocabulary leaks into the screen")
	assert_eq(view.has("unmet_conditions"), false, "no facade vocabulary leaks into the screen")
	screen.free()


func test_screen_actions_change_real_state() -> void:
	var screen := _screen()
	var actor := Actor.new(&"acts", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	screen.setup(actor)
	var before := float(screen.summary().get("progress", 0.0))
	screen.act_cultivate()
	var after := float(screen.summary().get("progress", 0.0))
	assert_eq(after > before, true, "cultivate moved real progress")
	assert_eq(screen.summary().get("tone", ""), "ok", "the outcome is reported")
	screen.free()


func test_breakthrough_is_refused_when_the_gate_is_not_met() -> void:
	var screen := _screen()
	var actor := Actor.new(&"gated", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	screen.setup(actor)
	assert_eq(screen.act_breakthrough(), false, "no pill, no channels, no advance")
	assert_eq(actor.path(QiPath.PATH_ID).rank_id, &"qi_refining", "the realm is unchanged")
	assert_eq(screen.summary().get("tone", ""), "error", "the refusal is explained")
	screen.free()


func test_screen_nests_its_child_panel_summaries() -> void:
	var screen := _screen()
	var actor := Actor.new(&"nested", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	screen.setup(actor)
	var view := screen.summary()
	var vitals: Dictionary = view.get("vitals", {})
	assert_eq(vitals.has("qi"), true, "the qi row reports")
	assert_eq(vitals.has("dantian"), true, "the dantian row reports")
	# The row owns the format, so the screen carries raw values.
	assert_eq(vitals.get("qi", {}).get("current", 0.0), 100.0, "raw value, not a string")
	screen.free()


func test_screen_records_focus_without_a_viewport() -> void:
	var screen := _screen()
	var actor := Actor.new(&"focus", {Stat.PHYSIQUE: 20.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	screen.setup(actor)
	screen.focus_initial()
	assert_eq(screen.summary().get("focus_target", ""), "CultivateButton", "cultivate lands focus")
	screen.free()


func test_stack_hooks_exist_on_every_screen() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	assert_eq(screen.summary(), {}, "the hooks are safe with no actor")
	assert_eq(screen.on_stack_input(null), false, "input is declined so the stack can pop")
	screen.free()
