extends TestCase

## The UI program is a pure consumer of the `body_cultivation` facade (ADR 0028).
## These tests assert `summary()` and the panel actions, never pixels, and drive the
## screens with no scene tree so `@onready` could not have been used.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const VITALS := "res://src/ui/panels/body_vitals_panel.tscn"


func _screen() -> BodyCultivationPanel:
	var panel := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	# Guard: a scene whose root script is unattached instantiates as a bare
	# Control, every cast below silently yields null, and each test then passes
	# against `{}`. Assert the wiring instead of trusting the cast.
	assert_ne(panel, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return panel


func _vitals() -> BodyVitalsPanel:
	var panel := (load(VITALS) as PackedScene).instantiate() as BodyVitalsPanel
	assert_ne(panel, null, "body_vitals_panel.tscn roots a BodyVitalsPanel")
	return panel


func _actor() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"body_ui_hero", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	assert_ne(ItemsApi.inventory(actor), null, "the actor carries an inventory")
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 999
	ItemsApi.inventory(actor).add(def, quantity)


## Bring the actor to the brink of the next realm through public actions.
func _prepare(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	var home := BodyRealmSeed.for_realm(state.rank_id)
	_stock(actor, seed.breakthrough_item)
	_stock(actor, home.strengthening_item, 400)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		var guard := 0
		while actor.meridians.refine_meridian(meridian_id, seed.required_refinement) and guard < 32:
			guard += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	var meditate_guard := 0
	while (
		meditate_guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate_guard += 1
		BodyTraining.meditate(actor, 1.0)
	return seed


# --- Headless contract ------------------------------------------------------


## The screen must be drivable with no scene tree at all: that is what proves it
## does not depend on `@onready` binding or a `_ready()`-time focus grab.
func test_screen_summary_works_without_a_scene_tree() -> void:
	var panel := _screen()
	assert_eq(panel.summary().is_empty(), true, "no view without an actor")
	var actor := _actor()
	panel.setup(actor)
	var view := panel.summary()
	assert_eq(view.get("realm", ""), String(&"qi_refining"), "reads the facade with no tree")
	panel.free()


## The screen must actually find its child row and its buttons. This is the
## regression that caught a scene root with no `script`, which made every other
## test in this file pass against an empty dictionary.
func test_the_screen_binds_its_child_row_and_buttons() -> void:
	var panel := _screen()
	panel.setup(_actor())
	var view := panel.summary()
	assert_ne(view.get("vitals", {}), {}, "the vitals row is bound and populated")
	assert_eq(bool(view.get("vitals", {}).get("bound", false)), true, "labels resolved")
	assert_eq(
		int(view.get("vitals", {}).get("acupoints", 0)),
		AcupointDefaults.MINOR_COUNT,
		"the row sees the huyệt"
	)
	panel.free()


func test_summary_without_an_actor_is_empty_not_partial() -> void:
	var panel := _screen()
	assert_eq(panel.summary(), {}, "empty when no actor")
	panel.free()


func test_summary_is_primitives_with_a_nested_child_summary() -> void:
	var panel := _screen()
	panel.setup(_actor())
	var view := panel.summary()
	assert_eq(view.has("vitals"), true, "child panel summary is nested")
	assert_eq(view.has("actions"), true, "action state is exposed")
	assert_eq(view.has("focus_target"), true, "focus route is exposed")
	var vitals: Dictionary = view["vitals"]
	for key in vitals.keys():
		assert_eq(
			(
				vitals[key] is Array
				or vitals[key] is float
				or vitals[key] is int
				or vitals[key] is String
				or vitals[key] is bool
				or vitals[key] is Dictionary
			),
			true,
			"vitals.%s is a primitive or array" % key
		)
	assert_eq(vitals.is_empty(), false, "the vitals row is populated")
	assert_eq(bool(vitals.get("bound", false)), true, "the row resolved its labels")
	assert_eq(
		int(vitals.get("acupoints", 0)), AcupointDefaults.MINOR_COUNT, "the row sees the huyệt"
	)
	panel.free()


func test_summary_reports_unmet_conditions_before_preparation() -> void:
	var panel := _screen()
	panel.setup(_actor())
	var view := panel.summary()
	assert_eq(view.get("target", ""), String(&"foundation"), "next realm shown")
	assert_eq(view.get("ready", true), false, "not ready yet")
	assert_ne(view.get("unmet", []), [], "unmet conditions are listed")
	assert_ne(view.get("channels", []), [], "channels listed")
	panel.free()


func test_breakthrough_is_offered_only_when_the_gate_is_met() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	assert_eq(panel.summary()["actions"]["breakthrough"], false, "blocked before preparation")
	assert_ne(_prepare(actor), null, "prepared")
	panel.refresh()
	assert_eq(panel.summary()["actions"]["breakthrough"], true, "offered once prepared")
	panel.free()


# --- Step sizes come from the facade ----------------------------------------


## A screen must not hardcode a step size; the facade publishes it.
func test_step_sizes_come_from_the_facade() -> void:
	var panel := _screen()
	panel.setup(_actor())
	var steps: Dictionary = panel.summary().get("steps", {})
	assert_eq(steps.size(), 2, "the facade publishes both step sizes")
	assert_eq(float(steps.get("cultivate", 0.0)) > 0.0, true, "a cultivate step is sized")
	assert_eq(float(steps.get("meditate", 0.0)) > 0.0, true, "a meditate step is sized")
	assert_eq(
		steps.get("cultivate", 0.0), BodyCultivationApi.STEPS["cultivate"], "one source of truth"
	)
	panel.free()


# --- Focus -----------------------------------------------------------------


## Focus is routed by the ScreenStack through `focus_initial()`, never grabbed in
## `_ready()`. The hook must exist and record a target with no viewport present.
func test_focus_is_routed_through_the_stack_hook() -> void:
	var panel := _screen()
	panel.setup(_actor())
	assert_eq(panel.has_method(&"focus_initial"), true, "the stack hook exists")
	panel.focus_initial()
	assert_eq(
		panel.summary().get("focus_target", ""), "CultivateButton", "cultivate is the landing spot"
	)
	panel.free()


func test_on_screen_shown_routes_focus() -> void:
	var panel := _screen()
	panel.setup(_actor())
	panel.on_screen_shown()
	assert_eq(panel.summary().get("focus_target", ""), "CultivateButton", "shown routes focus")
	panel.free()


# --- The vitals row owns the formatting -------------------------------------


## The screen passes raw values down; the panel owns `%d/%d` and decimals.
func test_vitals_row_is_empty_without_state() -> void:
	var vitals := _vitals()
	assert_ne(vitals, null, "the vitals row instantiates")
	assert_eq(vitals.summary(), {}, "empty panel reports empty")
	vitals.set_state({})
	assert_eq(vitals.summary(), {}, "still empty after an empty state")
	vitals.free()


## The row must render into real labels, not just report a dictionary. This is
## the contract a scene-root-without-script silently violated.
func test_vitals_row_renders_into_its_labels() -> void:
	var vitals := _vitals()
	vitals.set_state(BodyCultivationApi.panel_state(_actor()))
	assert_eq(bool(vitals.summary().get("bound", false)), true, "labels resolved from the scene")
	vitals.free()


func test_vitals_row_nests_under_the_screen_summary() -> void:
	var vitals := _vitals()
	vitals.set_state(BodyCultivationApi.panel_state(_actor()))
	var view := vitals.summary()
	assert_eq(view.get("realm", ""), String(&"qi_refining"), "realm surfaced")
	assert_eq(view.get("acupoints", 0), AcupointDefaults.MINOR_COUNT, "huyệt surfaced")
	assert_eq(view.get("ready", true), false, "gate surfaced")
	assert_eq(view.get("unmet", []) is Array, true, "unmet is an array of strings")
	vitals.free()


# --- Actions ----------------------------------------------------------------


func test_actions_change_body_state() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	var before_progress := actor.path(BodyPath.PATH_ID).progress
	panel.act_cultivate()
	assert_eq(actor.path(BodyPath.PATH_ID).progress > before_progress, true, "progress grew")
	panel.act_meditate()
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION) > 0.0, true, "comprehension grew")
	# Channel training needs the current realm's elixir; without it the panel is a
	# no-op rather than an error.
	assert_eq(panel.act_strengthen(), false, "no elixir, no training")
	assert_eq(actor.meridians.get_meridian(&"lung").state, &"closed", "lung untouched")
	var home := BodyRealmSeed.for_realm(&"qi_refining")
	_stock(actor, home.strengthening_item)
	assert_eq(panel.act_strengthen(), true, "channel trained")
	assert_ne(actor.meridians.get_meridian(&"lung").state, &"closed", "lung advanced")
	panel.free()


func test_breakthrough_is_a_noop_when_unprepared() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	assert_eq(panel.act_breakthrough(), false, "unprepared, no advance")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"qi_refining", "realm unchanged")
	panel.free()


func test_recover_is_a_noop_without_damage() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	assert_eq(panel.act_recover(), false, "nothing damaged, nothing repaired")
	panel.free()


func test_breakthrough_advances_once_prepared() -> void:
	var panel := _screen()
	var actor := _actor()
	panel.setup(actor)
	assert_ne(_prepare(actor), null, "prepared for the next realm")
	# The panel rolls the shared RNG, so attempts are swept across seeds and the
	# body is re-prepared after each deviation.
	var advanced := false
	for attempt in 32:
		seed(attempt + 1)
		if panel.act_breakthrough():
			advanced = true
			break
		_prepare(actor)
	assert_eq(advanced, true, "breakthrough eventually succeeded")
	assert_eq(actor.path(BodyPath.PATH_ID).rank_id, &"foundation", "realm advanced")
	assert_eq(panel.summary().get("realm", ""), String(&"foundation"), "panel re-read the realm")
	panel.free()
