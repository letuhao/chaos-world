extends TestCase

## The mind cultivation screen (ADR 0038/0042). Asserts `summary()` with no
## scene tree, and that the facade's own step sizes are what the screen reports —
## the screen must not invent its own numbers.

const SCREEN := "res://src/ui/screens/mind_cultivation_screen.tscn"


func _screen() -> MindCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as MindCultivationScreen


func _actor() -> Actor:
	var actor := Actor.new(&"mind_ui_hero", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	return actor


func test_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not partial")
	screen.free()


func test_summary_uses_the_shared_vocabulary() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	for key in ["realm", "target", "progress", "can_act", "chance", "unmet", "costs"]:
		assert_eq(view.has(key), true, "%s is in the shared vocabulary" % key)
	# The mind facade names the realm `rank`; the screen normalizes it so no two
	# screens disagree about the key.
	assert_eq(view.has("rank"), false, "no facade vocabulary leaks into the screen")
	assert_eq(view.has("has_path"), false, "no facade vocabulary leaks into the screen")
	screen.free()


func test_step_sizes_come_from_the_facade() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var steps: Dictionary = screen.summary().get("steps", {})
	assert_eq(
		float(steps.get("cultivate", 0.0)),
		MindCultivationApi.CULTIVATE_STEP,
		"the cultivate step is the facade's, not the screen's"
	)
	assert_eq(
		float(steps.get("meditate", 0.0)),
		MindCultivationApi.MEDITATE_STEP,
		"the meditate step is the facade's, not the screen's"
	)
	screen.free()


func test_sea_vitals_are_reported_as_raw_values() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var vitals: Dictionary = screen.summary().get("vitals", {})
	for key in ["mind_power", "clarity", "purity"]:
		assert_eq(vitals.has(key), true, "%s row reports" % key)
	# The row owns the format, so the screen carries raw numbers.
	assert_eq(vitals.get("clarity", {}).get("current", -1.0), 0.5, "raw clarity")
	assert_eq(vitals.get("clarity", {}).get("text", ""), "0.50/1.00", "the row formats it")
	screen.free()


func test_meditation_steadies_the_sea() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var before := float(screen.summary().get("turbulence", 0.0))
	screen.act_meditate()
	var after := float(screen.summary().get("turbulence", 0.0))
	assert_eq(after <= before, true, "meditation never raises turbulence")
	assert_eq(screen.summary().get("tone", ""), "ok", "the outcome is reported")
	screen.free()


func test_breakthrough_is_refused_when_the_gate_is_not_met() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	assert_eq(screen.act_breakthrough(), false, "no pill and no work, no advance")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "the realm is unchanged")
	assert_eq(screen.summary().get("tone", ""), "error", "the refusal is explained")
	screen.free()


func test_breakthrough_is_offered_only_when_the_gate_is_met() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var actions: Dictionary = screen.summary().get("actions", {})
	assert_eq(actions.get("enabled", {}).get("breakthrough", true), false, "blocked to start")
	assert_ne(screen.summary().get("unmet", []), [], "the reason is listed")
	screen.free()


func test_focus_lands_on_meditation() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.focus_initial()
	assert_eq(
		screen.summary().get("focus_target", ""), "MeditateButton", "meditation is the first move"
	)
	screen.free()
