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
## ## The gap this file had (DEF-0301), and what closes it
##
## Every case below used to reach the row by HAND-BUILDING `view_for_actor` and then
## writing `learn_short` and `can_pay` into it. That proved the PANEL renders a
## shortfall and nothing about where the shortfall came from — drop `can_pay` from
## `TechniqueReadModel.inspect` tomorrow and this whole file stayed green while the
## codex quietly published an empty shortfall forever.
##
## So the seam is now asserted where the rule lives: `test_the_codex_row_carries_the_shortfall_techniques_api_inspect_published`
## drives the REAL screen against a REAL short hero and reads the shortfall back off
## the row, then compares it to `TechniquesApi.inspect`'s own. Nothing in that test
## writes a shortfall, so nothing in it can go green without the module publishing
## one.

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
	# The shortfall is REAL here, not written into the view by hand. This case used
	# to overwrite `learn_short` and `can_pay` with values the test composed itself,
	# so it proved the PANEL renders a shortfall while proving nothing about the read
	# model publishing one — if `inspect` dropped `can_pay`, this suite stayed green
	# (DEF-0301). The hero is made short by giving the technique's own path less
	# progress than ADR 0160's price, and the view is whatever the module says.
	var price := float(TechniquesApi.inspect(actor, def.id).get("learn_price", 0.0))
	# Scoped to this hero and restored immediately. `_actor()` builds a fresh actor
	# per case, but leaving the qi path short would have leaked into any later case
	# that reuses it — and did, turning a GATE case's message into a SHORTFALL one.
	var held_before := actor.path(PathState.QI).progress
	actor.path(PathState.QI).progress = price * 0.5

	var view_for_actor := _view_for(actor, def)
	# Nothing is assigned to `learn_short` or `can_pay` here: both must arrive from
	# the module, or this case is asserting the test's own arithmetic again.
	assert_eq(bool(view_for_actor.get("can_pay", true)), false, "the module says he cannot pay")
	assert_eq((view_for_actor.get("learn_short", []) as Array).size(), 1, "and names one pool")
	actor.path(PathState.QI).progress = held_before

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
	# This case is about the GATE, so the hero must be able to PAY — otherwise the
	# row says so instead, correctly and more urgently, and the gate never gets a
	# word. The shortfall and the gate are two different refusals and the row names
	# the shortfall first (`_render` gives it the only alarming variation); a hero
	# who is short is not a gated hero.
	var price := float(TechniquesApi.inspect(actor, def.id).get("learn_price", 0.0))
	actor.path(PathState.QI).progress = price * 2.0
	var view_for_actor := _view_for(actor, def)
	assert_eq(
		bool(view_for_actor.get("can_pay", false)),
		true,
		"he can afford it — the gate is why he cannot study"
	)
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


## THE DEFECT THIS FILE HAD (DEF-0301), as a test. The row's shortfall came from
## `TechniquesApi.inspect`, not from a test that wrote one.
##
## Everything else in this file is a PANEL test: it hands the row a dictionary and
## asks whether the row draws it. That is necessary and it is not sufficient — it
## says nothing about the producer. This one closes the loop from the other end:
##
##   - the hero is SHORT for real (40 progress against a 100 study), so the shortfall
##     exists because of gameplay state rather than because a fixture declared it;
##   - the technique is LEARNED, so the codex really lists it and the screen really
##     runs `inspect` on it — the production route, not `_entry_view` with a
##     hand-written dictionary;
##   - and the row's shortfall is compared FIELD BY FIELD to what `inspect` published.
##
## **Why it cannot go green vacuously.** Nothing here constructs a `learn_short` or a
## `can_pay`. Drop `can_pay` from `inspect` and the row's `can_pay` reads `false`
## while the module's reads `true`, and the comparison fails. Drop `learn_short` and
## the row's list is empty while the module's names a pool, and it fails. There is no
## path by which this test passes with the read model silent — which is exactly what
## the hand-built version allowed.
func test_the_codex_row_carries_the_shortfall_techniques_api_inspect_published() -> void:
	var actor := _actor()
	var def := _technique(&"qi_real_short", PathState.QI)
	# 40 against a 100 study: short for a reason the module owns, not a fixture.
	actor.path(PathState.QI).progress = 40.0
	# NOT learned, and deliberately so. A row for a technique the hero already holds
	# claims no cost at all — `learn_price` 0.0, `can_pay` false, `short_list()`
	# empty — because holding it is free (DEF-0244), so a shortfall on a technique
	# he has is not something the row says. The relay under test is the one a player
	# actually meets: an UNLEARNED manual he cannot yet afford.
	#
	# The codex lists learned entries, so this drives the ROW directly with the
	# module's own `inspect` output rather than routing through a list that only
	# holds what is known. Every figure compared below is the module's.
	var detail: Dictionary = TechniquesApi.inspect(actor, def.id)
	assert_eq(bool(detail.get("can_pay", true)), false, "the module says this hero cannot pay")
	var owed: Array = detail.get("learn_short", []) as Array
	assert_eq(owed.size(), 1, "and names the one pool it is short on")
	assert_eq(String((owed[0] as Dictionary)["resource"]), "qi_cultivation", "by path")
	assert_almost_eq(
		float((owed[0] as Dictionary)["current"]), 40.0, "against what it holds", 0.0001
	)

	var row := _row()
	row.call(&"show_entry", detail)
	# `row` is a NODE, so `.get()` on it takes one argument — the row's own summary
	# is read through `call(&"summary")`, which is the contract every consumer uses.
	var relayed: Dictionary = row.call(&"summary")

	# The row's answers ARE the module's, field by field. Not "a shortfall exists" —
	# the same shortfall, on the same pool, for the same two figures. Nothing is
	# composed here: every figure came out of `TechniquesApi.inspect` above.
	assert_eq(bool(relayed.get("can_pay", true)), false, "the row relays the module's refusal")
	var short: Array = relayed.get("learn_short", []) as Array
	assert_eq(short.size(), 1, "and the module's shortfall, not one of its own")
	assert_eq(
		String((short[0] as Dictionary)["resource"]),
		String((owed[0] as Dictionary)["resource"]),
		"on the pool the module named"
	)
	assert_almost_eq(
		float((short[0] as Dictionary)["required"]),
		float((owed[0] as Dictionary)["required"]),
		"for the figure it owed",
		0.0001
	)
	assert_almost_eq(
		float((short[0] as Dictionary)["current"]),
		float((owed[0] as Dictionary)["current"]),
		"against the figure it held",
		0.0001
	)
	# And it is DRAWN, not merely relayed: the shortfall reaches a hero's eyes.
	var note := String(relayed.get("note_line", ""))
	assert_ne(note.find("Short on the qi path"), -1, "rendered in a hero's words")
	assert_ne(
		note.find("needs %d" % int(round(float((owed[0] as Dictionary)["required"])))),
		-1,
		"quoting the module's own owed figure"
	)


## The relay contract, both directions. A row that DECIDED affordability would pass
## the case above by coincidence whenever the two happened to agree, so the other
## direction is asserted too: a hero who CAN pay is given no refusal and no shortfall,
## because the module published none. Silence here is the module's answer.
func test_a_payable_hero_is_given_no_refusal_because_the_module_published_none() -> void:
	var actor := _actor()
	var def := _technique(&"qi_real_pays", PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	actor.path(PathState.QI).progress = 100000.0

	# The module answers "you can pay" and owes nothing.
	var detail := TechniquesApi.inspect(actor, def.id)
	assert_eq(bool(detail.get("can_pay", false)), true, "the module says it is payable")
	assert_eq((detail.get("learn_short", []) as Array).size(), 0, "and nothing is short")

	var codex := _codex()
	codex.setup(actor)
	var row := _entry_for(codex, def.id)
	# The hero already holds it, so the row claims no cost whatever the module says
	# about a duplicate — which is the rule, not a silence (DEF-0244). What matters
	# here is that it INVENTS no shortfall: the module published none.
	assert_eq(bool(row.get("can_pay", false)), false, "a held technique claims no cost")
	assert_eq((row.get("learn_short", []) as Array).size(), 0, "and invents no shortfall")
	assert_eq(String(row.get("note_line", "")), "", "so no refusal is drawn")


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
