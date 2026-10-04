extends TestCase

## DEF-0244: a hero was never told what a technique costs to learn before
## `use_item` consumed the manual. The price was computed and published; no player
## action reached it.
##
## ## What these tests hold still
##
## The defect class is PUBLISHED BUT UNREACHABLE, so every assertion here reads a
## value off `summary()` — the string a label would show and the numbers it would
## print — rather than asserting that some function got called. A row that
## published a price and rendered nothing would pass a "calls `inspect`" test and
## fail every one of these.
##
## ## The seam under test
##
## `TechniquesApi.inspect` publishes `learn_price` and `learn_unmet` today. It does
## NOT publish affordability: grepping `can_pay` across `modules/techniques/` finds
## nothing, and `TechniquesApi._short` is private, reachable only through the `learn`
## OUTCOME — i.e. after the press. So these tests drive the screen the way
## production will feed it: with whatever the facade actually published, plus the
## shortfall when a caller supplies one.
##
## That is deliberate rather than a workaround. Re-deriving ADR 0160's payer rule in
## `ui/` to synthesise `can_pay` would put a gameplay rule behind the facade — the
## screen would claim an affordability the module never answered, and would be wrong
## the day the module changed its payer. The relay contract is the honest shape, and
## it is asserted here so a future facade extension lands on a tested seam rather
## than a second one.

const CODEX_SCENE := "res://src/ui/screens/technique_codex.tscn"
const ROW_SCENE := "res://src/ui/panels/technique_entry_row.tscn"
const MORTAL := &"qi_refining"

var _screen: UiScreen = null
var _row_ref: TechniqueEntryRow = null


func teardown() -> void:
	_release_row()
	_screen = null


func _release_row() -> void:
	if _row_ref != null and is_instance_valid(_row_ref):
		_row_ref.free()
	_row_ref = null


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


func _row() -> TechniqueEntryRow:
	# Not `_mount`: that one is typed `UiScreen`, and a row is a `PanelContainer`, so
	# the cast would not resolve at parse time. Tracked separately so `teardown`
	# still frees it rather than leaking a node per call.
	_release_row()
	var row: TechniqueEntryRow = load(ROW_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(row)
	_row_ref = row
	return row


## A hero on all three paths with the techniques module attached, which is what a
## screen meets at boot.
func _actor(realm_id: StringName = MORTAL) -> Actor:
	var actor := Actor.new(&"study_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 400.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.set_path(PathState.new(PathState.BODY, realm_id))
	actor.set_path(PathState.new(PathState.MIND, realm_id))
	TechniquesApi.attach(actor)
	return actor


## A passive on `path_id`, registered the way a `.tres` would be.
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


## The shortfall shape `TechniquesApi._short` publishes, so the tests feed the
## screen the module's own vocabulary rather than one invented for the test.
func _short(path_id: String, required: float, current: float) -> Dictionary:
	return {"resource": path_id, "required": required, "current": current}


## The codex row for one technique id, or `{}` when the page does not list it.
func _entry_for(screen: UiScreen, technique_id: StringName) -> Dictionary:
	for entry in screen.summary()["entries"] as Array:
		var view: Dictionary = entry as Dictionary
		if String(view.get("id", "")) == String(technique_id):
			return view
	return {}


# --- The price reaches a hero ------------------------------------------------


## THE DEFECT, as a test. An UNLEARNED technique's entry publishes the price the
## module computed, so a page that shows this entry states what the study costs.
##
## The price is the module's own figure, read back through `inspect` rather than
## hardcoded, so this asserts a value a player sees equals the charge that would
## actually be paid — and so it fails if the screen stops relaying the price at
## all.
func test_an_unlearned_entry_publishes_the_price_the_module_computes() -> void:
	var actor := _actor()
	var def := _technique(&"qi_unlearned_price", PathState.QI)
	var expected := float(TechniquesApi.inspect(actor, def.id)["learn_price"])
	assert_ne(expected, 0.0, "the module prices this technique at something")

	var codex := _codex()
	codex.setup(actor)
	# Put the unlearned technique on the page the way a caller supplies one: the
	# codex lists LEARNED entries (ADR 0053), so the row under test is fed the
	# entry view this screen builds for it.
	var row := _row()
	row.call(&"show_entry", _view_for(actor, def))
	var view: Dictionary = row.call(&"summary")

	assert_eq(bool(view["known"]), false, "the hero has not learned it")
	assert_eq(float(view["learn_price"]), expected, "published at the module's own price")
	assert_ne(String(view["price_line"]), "", "and the row renders a price line")
	assert_ne(String(view["price_line"]).find(str(int(round(expected)))), -1, "quoting the figure")
	assert_eq(
		String(view["price_line"]),
		"Not learned - costs %d progress" % int(round(expected)),
		"in words"
	)


## The price is printed, not merely published. A row that held the number in
## `summary()` and rendered an empty label would satisfy every other test here and
## tell a hero nothing.
func test_the_price_line_is_rendered_into_the_row_and_reaches_a_label() -> void:
	var actor := _actor()
	var def := _technique(&"qi_price_rendered", PathState.QI)
	var row := _row()
	row.call(&"show_entry", _view_for(actor, def))
	var label := row.get_node_or_null("%PriceLabel") as Label
	assert_eq(label != null, true, "the row has a price label")
	assert_ne(label.text, "", "and it shows something")
	assert_ne(label.text.find("Not learned"), -1, "naming the state")
	assert_eq(
		label.text,
		String((row.call(&"summary") as Dictionary)["price_line"]),
		"label matches summary"
	)


# --- Can this actor pay? ----------------------------------------------------


## The shortfall is SHOWN, not just the price: which pool, what was owed, what was
## held. A price a hero cannot compare against their own progress is half a feature,
## so the row states all three in the module's own `{resource, required, current}`
## vocabulary.
func test_a_short_hero_is_shown_the_shortfall_not_just_the_price() -> void:
	var actor := _actor()
	var def := _technique(&"qi_short_hero", PathState.QI)
	var view_for_actor := _view_for(actor, def)
	var price := float(view_for_actor["learn_price"])
	view_for_actor["learn_short"] = [_short("qi_cultivation", price, price * 0.5)]
	view_for_actor["can_pay"] = false

	var row := _row()
	row.call(&"show_entry", view_for_actor)
	var view: Dictionary = row.call(&"summary")

	# The price is still there — the shortfall replaces it only with more truth.
	assert_eq(float(view["learn_price"]), price, "the price is still published")
	# And the shortfall names the pool, the owed figure and the held figure.
	var short: Array = view["learn_short"]
	assert_eq(short.size(), 1, "one pool is short")
	assert_eq(String((short[0] as Dictionary)["resource"]), "qi_cultivation", "names the pool")
	assert_eq(float((short[0] as Dictionary)["required"]), price, "what was owed")
	assert_eq(float((short[0] as Dictionary)["current"]), price * 0.5, "and what was held")
	assert_eq(bool(view["can_pay"]), false, "so this actor cannot pay")
	# Rendered, in a hero's words rather than the module's path id.
	var note := String(view["note_line"])
	assert_ne(note.find("Short on the qi path"), -1, "names the pool in words")
	assert_ne(note.find("needs %d" % int(round(price))), -1, "and what is owed")
	assert_ne(note.find("held %d" % int(round(price * 0.5))), -1, "and what is held")
	assert_eq(
		(row.get_node_or_null("%NoteLabel") as Label).text, note, "the shortfall is on a label"
	)


## A shortfall is a refusal, so it is the one line on this row that takes the
## theme's alarming variation. A hero who is short must not read it in the same ink
## as an ordinary price.
func test_a_shortfall_is_styled_as_a_refusal_and_a_clear_price_is_not() -> void:
	var actor := _actor()
	var def := _technique(&"qi_short_styled", PathState.QI)
	var short_view := _view_for(actor, def)
	short_view["learn_short"] = [_short("qi_cultivation", 900.0, 12.0)]

	var row := _row()
	row.call(&"show_entry", short_view)
	var note := row.get_node_or_null("%NoteLabel") as Label
	assert_eq(note.theme_type_variation, &"WarnLabel", "a shortfall reads as a refusal")

	var clear_view := _view_for(actor, def)
	clear_view["learn_short"] = []
	clear_view["can_pay"] = true
	row.call(&"show_entry", clear_view)
	assert_eq(note.theme_type_variation, &"MetaLabel", "a payable price does not")


## A hero who CAN pay is told so by the absence of a shortfall rather than by a
## claim the screen cannot verify. The silence is the module's answer: the row
## prints no verdict it was not given.
func test_a_payable_hero_is_given_no_refusal_and_no_invented_shortfall() -> void:
	var actor := _actor()
	var def := _technique(&"qi_can_pay", PathState.QI)
	var view_for_actor := _view_for(actor, def)
	view_for_actor["learn_short"] = []
	view_for_actor["can_pay"] = true

	var row := _row()
	row.call(&"show_entry", view_for_actor)
	var view: Dictionary = row.call(&"summary")
	assert_eq(bool(view["can_pay"]), true, "the module says it is payable")
	assert_eq((view["learn_short"] as Array).size(), 0, "and nothing is short")
	assert_eq(String(view["note_line"]), "", "so no refusal is shown")
	assert_ne(String(view["price_line"]).find("costs"), -1, "the price is still quoted")


## The GATE is shown too, and it is not the same statement as a shortfall: one is
## a realm requirement, the other is a missing resource. Conflating them would hide
## one of the two reasons a hero cannot study.
func test_a_gated_technique_shows_the_gate_and_marks_the_price() -> void:
	var actor := _actor()
	var def := _technique(&"qi_gated", PathState.QI)
	var view_for_actor := _view_for(actor, def)
	view_for_actor["can_learn"] = false
	view_for_actor["learn_unmet"] = ["Requires qi realm 9 (you are at 1)"]

	var row := _row()
	row.call(&"show_entry", view_for_actor)
	var view: Dictionary = row.call(&"summary")
	assert_eq(
		String(view["price_line"]).ends_with("(gated)"), true, "the price line marks the gate"
	)
	# The gate is the module's own wording, relayed verbatim rather than restated.
	assert_eq(
		String(view["note_line"]), "Not yet: Requires qi realm 9 (you are at 1)", "shown in words"
	)
	assert_eq(
		String((view["learn_blocked_by"] as Array)[0]), "Requires qi realm 9 (you are at 1)", "raw"
	)


# --- A known technique costs nothing -----------------------------------------


## A LEARNED technique must not claim to cost anything.
##
## `inspect().learn_price` is the price of a DUPLICATE manual, and it is published
## for learned techniques too — so a row that passed it straight through told a
## consumer that holding a technique costs money. This asserts the row's claim, not
## the module's figure.
func test_a_learned_technique_does_not_claim_to_cost_anything() -> void:
	var actor := _actor()
	var def := _technique(&"qi_already_known", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)

	# The module still publishes a duplicate-manual price; the row must not claim it.
	assert_ne(
		float(TechniquesApi.inspect(actor, def.id)["learn_price"]),
		0.0,
		"the module does price a duplicate"
	)
	var row := _row()
	row.call(&"show_entry", _view_for(actor, def))
	var view: Dictionary = row.call(&"summary")

	assert_eq(bool(view["known"]), true, "the hero knows it")
	assert_eq(float(view["learn_price"]), 0.0, "and the row claims it costs nothing")
	assert_eq(String(view["price_line"]), "Known", "the line says so")
	# No refusal and no shortfall either: nothing about it is being asked for.
	assert_eq(String(view["note_line"]), "", "no refusal on a known technique")
	assert_eq((view["learn_short"] as Array).size(), 0, "and no shortfall")
	# Even when a caller supplies one, a known technique is not short of anything.
	var forced := _view_for(actor, def)
	forced["learn_short"] = [_short("qi_cultivation", 500.0, 1.0)]
	row.call(&"show_entry", forced)
	var known_view: Dictionary = row.call(&"summary")
	assert_eq(float(known_view["learn_price"]), 0.0, "still nothing to pay")
	assert_eq((known_view["learn_short"] as Array).size(), 0, "and still not short")
	assert_eq(String(known_view["note_line"]), "", "and still no refusal")


# --- The relay contract -----------------------------------------------------


## The screen does not DECIDE affordability, and the row does not either: both relay
## what the facade published. `TechniquesApi` publishes no `can_pay` today, so this
## pins the behaviour that matters — absent an answer, neither one invents a verdict.
func test_no_affordability_is_invented_when_the_facade_answers_nothing() -> void:
	var actor := _actor()
	var def := _technique(&"qi_no_answer", PathState.QI)
	var detail := TechniquesApi.inspect(actor, def.id)
	assert_eq(detail.has("can_pay"), false, "the module publishes no can_pay today")

	var view_for_actor := _view_for(actor, def)
	var row := _row()
	row.call(&"show_entry", view_for_actor)
	var view: Dictionary = row.call(&"summary")
	# The row reports what it was told, which is nothing.
	assert_eq(bool(view["can_pay"]), false, "nothing was claimed")
	assert_eq((view["learn_short"] as Array).size(), 0, "and no shortfall was invented")


## And the screen relays the facade's answer when there IS one, so the seam a future
## facade extension lands on is already tested rather than invented at the time.
func test_the_screen_relays_an_affordability_answer_when_the_facade_publishes_one() -> void:
	var actor := _actor()
	var def := _technique(&"qi_relayed", PathState.QI)
	var codex := _codex()
	codex.setup(actor)
	# The codex lists learned entries, so this is learned and priced as a duplicate;
	# the relay itself is what is under test.
	TechniquesApi.codex(actor).learn(def.id)
	var view := _entry_for(codex, def.id)
	assert_eq(view.has("learn_price"), true, "the entry carries the module's price")
	assert_eq(view.has("learn_short"), true, "and a shortfall field, normalised")
	assert_eq(view.has("can_pay"), true, "and an affordability field")


## The codex is still read-only: a preview must not become a second way to learn.
## ADR 0053 makes the ITEM deliver a technique, so a learn verb here would be a
## second door to one state.
func test_the_codex_publishes_no_way_to_learn() -> void:
	var codex := _codex()
	for action in [
		"learn",
		"act_learn",
		"study",
		"act_study",
		"equip",
		"act_equip",
		"unequip",
		"act_unequip",
	]:
		assert_eq(codex.has_method(action), false, "the codex publishes no '%s'" % action)
	# And a preview changes nothing: reading the page is not an action.
	var actor := _actor()
	var def := _technique(&"qi_preview_only", PathState.QI)
	codex.setup(actor)
	var before := actor.path(PathState.QI).progress
	_entry_for(codex, def.id)
	codex.summary()
	assert_eq(actor.path(PathState.QI).progress, before, "previewing spends nothing")


## The facade is still exactly twelve public methods. The preview cost nothing at
## the module, which is the point: no thirteenth verb was needed to answer "what
## does it cost".
func test_the_preview_added_no_facade_method() -> void:
	var published: Array[String] = []
	for method in TechniquesApi.new().get_script().get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(published.size(), 12, "still exactly twelve, found %d" % published.size())


## `summary()` is the contract and it is primitives-only: a consumer of this screen
## must never have to reach back into a module to read a shortfall.
func test_the_summary_publishes_primitives_only() -> void:
	var actor := _actor()
	var def := _technique(&"qi_primitives", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	var codex := _codex()
	codex.setup(actor)
	var view := _entry_for(codex, def.id)
	assert_ne(view.is_empty(), true, "the entry is published")
	for key in ["learn_price", "can_pay", "learn_short", "known", "price_line", "note_line"]:
		assert_eq(view.has(key), true, "'%s' is published" % key)
	assert_eq(view["learn_price"] is float or view["learn_price"] is int, true, "a number")
	assert_eq(view["can_pay"] is bool, true, "a bool")
	assert_eq(view["learn_short"] is Array, true, "an array")
	for pool in view["learn_short"] as Array:
		assert_eq(pool is Dictionary, true, "of dictionaries")
		for field in ["resource", "required", "current"]:
			assert_eq((pool as Dictionary).has(field), true, "each carries '%s'" % field)


## The no-actor contract survives the change: a screen with nobody bound publishes
## nothing, not an empty price.
func test_no_actor_still_reports_an_empty_summary() -> void:
	assert_eq(_codex().summary(), {}, "the codex reports nothing, not keys")


# --- Helpers ----------------------------------------------------------------


## The entry view this screen builds for `def`, assembled through the screen's own
## private builder so the tests exercise the real relay path rather than a fixture
## shaped to match the assertions. `_entry_view` is the function under test, so it
## is called the way `_read_and_feed` calls it.
func _view_for(actor: Actor, def: TechniqueDef) -> Dictionary:
	var codex := _codex()
	codex.setup(actor)
	var entry := {
		"id": String(def.id),
		"display_name": def.display_name,
		"grade": String(def.grade),
		"path": String(def.path),
		"active": def.active,
		"rung": 0,
	}
	var built: Dictionary = codex.call(&"_entry_view", entry)
	return built
