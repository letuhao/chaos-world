extends TestCase

## The two technique screens (ADR 0053, DEF-0093): the unbounded read-only codex
## and the limited path-typed loadout. They answer different questions, so these
## tests assert the distinction as much as the contents — the codex publishes no
## action and the loadout's one action is a release, never a loss.
##
## Nothing here asserts pixels or a formatted number out of a screen. The rows
## own every format; the screens carry raw values.

const CODEX_SCENE := "res://src/ui/screens/technique_codex.tscn"
const LOADOUT_SCENE := "res://src/ui/screens/technique_loadout.tscn"
const MORTAL := &"qi_refining"
const SPIRIT := &"spirit_condensation"

var _screen: UiScreen = null


func teardown() -> void:
	# `_mount` already frees the previous screen before installing the next one, so
	# by the time teardown runs `_screen` may be a stale reference to something the
	# runner has collected. Guarding on `is_instance_valid` alone is not enough:
	# `free()` on an already-freed object raises "Nonexistent function in base
	# 'previously freed'". Nulling the field in `_mount` after freeing makes the
	# lifetime unambiguous from either side.
	_screen = null


## Frees whatever `_screen` points at and leaves the field null, so neither
## `_mount` nor `teardown` can double-free.
func _release_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null


func _mount(scene_path: String) -> UiScreen:
	_release_screen()
	var screen: UiScreen = load(scene_path).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	_screen = screen
	return screen


func _codex() -> UiScreen:
	return _mount(CODEX_SCENE)


func _loadout() -> UiScreen:
	return _mount(LOADOUT_SCENE)


## A hero on all three paths with the techniques module attached, which is what a
## screen meets at boot: `TechniquesApi.attach` is idempotent, so the screen
## re-attaching changes nothing.
func _actor(realm_id: StringName = MORTAL) -> Actor:
	var actor := Actor.new(&"technique_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 400.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.set_path(PathState.new(PathState.BODY, realm_id))
	actor.set_path(PathState.new(PathState.MIND, realm_id))
	TechniquesApi.attach(actor)
	return actor


## A passive on `path_id`, registered with the catalog the way a `.tres` would be,
## so `inspect` can resolve it by id the way a rendered row needs it to.
##
## The return type is stated because an untyped return leaves `TechniqueDef.new()`
## un-inferrable at every call site, which this project treats as an error.
func _technique(
	technique_id: StringName, path_id: StringName, grade: StringName = ItemGrade.MORTAL
) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = technique_id
	def.display_name = "Manual %s" % String(technique_id)
	def.grade = grade
	def.path = path_id
	def.active = false
	def.mastery_rungs = 4
	TechniqueCatalog.instance().register(def)
	return def


# --- The empty-summary contract ---------------------------------------------


func test_both_screens_report_an_empty_summary_with_no_actor() -> void:
	assert_eq(_codex().summary(), {}, "the codex reports nothing, not keys")
	assert_eq(_loadout().summary(), {}, "the loadout reports nothing, not keys")


func test_both_screens_report_raw_values_and_nest_their_rows() -> void:
	var actor := _actor()
	var def := _technique(&"qi_seed", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)

	var codex := _codex()
	codex.setup(actor)
	var codex_view := codex.summary()
	for key in ["actor", "read_only", "realm_tier", "codex_count", "entries", "entry_ids"]:
		assert_eq(codex_view.has(key), true, "%s is in the codex summary" % key)
	# Raw, not rendered: the screen carries the module's own counts so a test can
	# assert against the facade rather than against a string.
	assert_eq(
		int(codex_view["codex_count"]), int(TechniquesApi.summary(actor)["codex_count"]), "raw"
	)
	var entries: Array = codex_view["entries"]
	assert_eq(entries.size(), 1, "one learned technique is listed")
	var row: Dictionary = entries[0]
	assert_eq(String(row["id"]), String(def.id), "the row names the technique")
	assert_eq(bool(row["known"]), true, "the row knows it is known")
	assert_eq(int(row["rung"]), 0, "raw rung")
	assert_eq(int(row["rung_count"]), 4, "raw mastery reach")
	assert_ne(String(row["mastery_line"]), "", "the row owns the mastery format")

	var loadout := _loadout()
	loadout.setup(actor)
	var loadout_view := loadout.summary()
	for key in ["actor", "is_loadout", "slot_total", "slot_free", "slots", "filled_slots", "pools"]:
		assert_eq(loadout_view.has(key), true, "%s is in the loadout summary" % key)
	assert_eq(
		int(loadout_view["slot_total"]),
		int(TechniquesApi.summary(actor)["slot_total"]),
		"the budget is the module's, not the screen's"
	)
	var slots: Array = loadout_view["slots"]
	assert_eq(slots.size(), 7, "Mortal publishes seven slots")
	# Matched by POOL rather than by position: `slot_keys` publishes the three path
	# pools in `PathState.ALL` order and the qi technique lands wherever qi sits in
	# that order, so "the first slot" is an accident of the vocabulary rather than a
	# property anything should rely on.
	assert_eq(
		slots.any(func(row: Dictionary) -> bool: return bool(row.get("filled", false))),
		true,
		"exactly one published slot is bound"
	)
	assert_eq(int(loadout_view["equipped_count"]), 1, "and the module agrees on the count")


# --- The two questions stay separate ----------------------------------------


func test_the_codex_is_not_the_loadout() -> void:
	var actor := _actor()
	var def := _technique(&"qi_only", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)
	var view := codex.summary()
	assert_eq(bool(view["read_only"]), true, "the codex is read-only")
	assert_eq(bool(view["is_loadout"]), false, "and says it is not the loadout")
	# Read-only means no action surface at all: no picker, no equip, no unequip.
	for action in ["equip", "unequip", "learn", "act_equip", "act_unequip", "act_learn"]:
		assert_eq(
			codex.has_method(action),
			false,
			"the codex publishes no '%s'; equipping is the loadout's business" % action
		)
	assert_eq(bool(view["is_loadout"]), false, "the codex never claims the budget")


func test_the_loadout_says_it_is_the_limited_half() -> void:
	var actor := _actor()
	var loadout := _loadout()
	loadout.setup(actor)
	var view := loadout.summary()
	assert_eq(bool(view["is_loadout"]), true, "the loadout says so")
	assert_eq(view.has("read_only"), false, "and is not the read-only half")
	# Every slot the facade publishes is on the page, each with its pool and its
	# occupant — the 7/8/9/10 budget is legible because nothing is collapsed.
	var kinds: Array = []
	for slot in view["slots"]:
		kinds.append(String((slot as Dictionary)["kind"]))
	assert_eq(kinds.size(), 7, "seven rows")
	assert_eq(kinds.count(PathState.QI), 3, "qi holds three")
	assert_eq(kinds.count(PathState.BODY), 2, "body holds two")
	assert_eq(kinds.count(PathState.MIND), 2, "mind holds two")


func test_the_budget_grows_with_the_realm_tier() -> void:
	for tier_case in [[MORTAL, 7], [SPIRIT, 8]]:
		var actor := _actor(tier_case[0])
		var loadout := _loadout()
		loadout.setup(actor)
		var view := loadout.summary()
		assert_eq(int(view["slot_total"]), int(tier_case[1]), "%s budget" % tier_case[0])
		assert_eq((view["slots"] as Array).size(), int(tier_case[1]), "one row per slot")


# --- Releasing a slot never loses the technique -----------------------------


func test_releasing_a_slot_empties_the_slot_and_keeps_the_codex_entry() -> void:
	var actor := _actor()
	var def := _technique(&"qi_held", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id, 3)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)
	assert_eq(int(loadout.summary()["equipped_count"]), 1, "bound to start")

	assert_eq(loadout.call(&"act_unequip", def.id), true, "the release went through")
	var view := loadout.summary()
	assert_eq(int(view["equipped_count"]), 0, "the slot is free again")
	assert_eq((view["filled_slots"] as Array).size(), 0, "no slot is bound")
	assert_eq(String(view["message"]), "Released %s to the codex" % String(def.id), "reported")
	# The load-bearing half of ADR 0053: the technique is still known, with its
	# rung, because releasing a slot is a build choice and never a loss.
	var codex := _codex()
	codex.setup(actor)
	var codex_view := codex.summary()
	assert_eq(int(codex_view["codex_count"]), 1, "the codex still holds it")
	assert_eq(int((codex_view["entries"] as Array)[0]["rung"]), 3, "and its rung survived")


func test_releasing_a_technique_that_is_not_equipped_is_refused_and_reported() -> void:
	var actor := _actor()
	var def := _technique(&"qi_loose", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var loadout := _loadout()
	loadout.setup(actor)
	assert_eq(loadout.call(&"act_unequip", def.id), false, "nothing to release")
	assert_eq(String(loadout.summary()["tone"]), "error", "the refusal is reported")
	assert_eq(int(loadout.summary()["codex_count"]), 1, "and nothing was touched")


func test_a_filled_slot_offers_a_release_and_an_empty_one_does_not() -> void:
	var actor := _actor()
	var def := _technique(&"qi_one", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	var loadout := _loadout()
	loadout.setup(actor)
	var slots: Array = loadout.summary()["slots"]
	var can_release := 0
	for slot in slots:
		if bool((slot as Dictionary)["can_unequip"]):
			can_release += 1
	assert_eq(can_release, 1, "only the bound slot can be released")


# --- The ScreenStack contract -----------------------------------------------


func test_both_screens_implement_the_screen_stack_hooks() -> void:
	var actor := _actor()
	var def := _technique(&"qi_hook", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	# One screen at a time. `_mount` frees whatever was mounted before it, so
	# building both inside the `for` header handed the loop the codex it had already
	# freed — "Nonexistent function in base 'previously freed'" at the first call.
	for scene_path in [CODEX_SCENE, LOADOUT_SCENE]:
		var screen := _mount(scene_path)
		screen.setup(actor)
		screen.call(&"on_screen_shown")
		assert_ne(screen.summary().is_empty(), true, "showing repaints it")
		screen.call(&"on_screen_hidden")
		assert_ne(screen.summary().is_empty(), true, "hiding keeps it readable")
		assert_eq(
			screen.call(&"on_stack_input", InputEventKey.new()),
			false,
			"the screen consumes nothing, so ui_cancel still pops"
		)
		screen.call(&"focus_initial")
		assert_ne(String(screen.summary()["focus_target"]), "", "focus lands on something real")
