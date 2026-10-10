extends "res://tests/ui/custody_surface_fixture.gd"

## ## This file holds the CONTRACT half of the custody surface
##
## What the screen must show before any claim is taken, what the row panel owns, and
## every boundary read off the SHIPPED source rather than asserted about this suite: the
## ADR 0104 prose ban, the one-facade rule, the published route and the key it is bound
## to, the three bans the UI standard states, and the scene's anchors-and-Containers
## composition.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every case below is the original body verbatim, and every constant, the
## `setup()` / `teardown()` pair and the helper it uses live in
## `custody_surface_fixture.gd`, which this file `extends`.
##
## The slice half -- capture, transfer, settlement and release driven the way a player
## does -- is `test_custody_surface.gd`.

# --- the screen contract -----------------------------------------------------

## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state

## unreadable rather than merely empty.

##

## ## The floor of TWO is why this has a second assertion

##

## This body was one assertion long on its first run, and the suite's declared floor

## caught it — an aborted body records neither a pass nor a failure, so a one-assertion

## test can die half way and report green. So the second claim here is the one that

## matters most: **staging is not state.** A screen that reported its own staged beat as

## part of `summary()` would render a page whose whole content is a claim nobody has

## taken yet, and every probe would read that as a real world.


func test_the_screen_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()

	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 2)

	assert_eq(
		screen.summary(),
		{},
		"and still empty with a beat staged: staging is the CALLER's input, never state"
	)

	screen.free()


## Every claim in the ledger is a row, and NONE is truncated. The pool grows through

## `RowBudget.cap`, so a cap low enough to bite would silently drop a claim off the end

## — and the count is asserted against the LEDGER rather than against the pool.


func test_every_claim_is_listed_rather_than_truncated() -> void:
	var screen := _bound()

	var held := int(CustodyApi.summary(_held[0])["claim_count"])

	# Two distinct subjects, so the board is more than one row and the sort has to order

	# them rather than falling out of a one-element list.

	var others: Array[String] = []

	for subject in [SECOND_SUBJECT]:
		var holder := _actor(StringName("holder_%s" % String(subject)))

		_held.append(holder)

		var taken := CustodyApi.capture(holder, subject, &"npc", _owner(holder.id), TERM, 2)

		assert_eq(bool(taken["ok"]), true, "setup: a second claim opens")

		others.append(String(taken["claim_id"]))

	screen.refresh()

	# The shared ledger means this hero's page shows EVERY claim, whoever opened it —

	# which is ADR 0101's whole answer for a world fact.

	assert_eq(
		int(screen.summary()["claim_count"]),
		held + others.size(),
		"the page lists every claim in the ledger, not a per-actor subset"
	)

	assert_eq(
		screen.claim_ids().size(),
		screen.summary()["claim_count"],
		"the pickable list and the reported count agree, so no row was truncated"
	)

	screen.free()


## The pick walks the SHOWN list and is declined on an empty one — which is what keeps

## `ui_cancel` free by association.


func test_the_pick_walks_the_shown_list_and_accept_releases_what_this_hero_holds() -> void:
	var screen := _bound()

	var down := InputEventAction.new()

	down.action = &"ui_down"

	down.pressed = true

	assert_eq(screen.on_stack_input(down), false, "down on an empty board is declined")

	assert_eq(screen.on_stack_input(null), false, "and a null event is too")

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	assert_eq(screen.on_stack_input(down), true, "down picks the first claim")

	assert_eq(
		String(screen.summary()["selected_claim"]),
		String(captured["claim_id"]),
		"and it is the one that was just opened"
	)

	# `ui_accept` fires the verb the pick's own state makes primary — release, for a

	# claim THIS hero holds.

	var accept := InputEventAction.new()

	accept.action = &"ui_accept"

	accept.pressed = true

	assert_eq(screen.on_stack_input(accept), true, "accept is consumed, because it did something")

	assert_eq(
		String(screen.summary()["last_reason"]),
		"",
		"and what it did was the release, which succeeds"
	)

	var claim: Dictionary = (CustodyApi.summary(_held[0])["claims"] as Dictionary)[String(
		captured["claim_id"]
	)]

	assert_eq(String(claim["status"]), "released", "so the claim reads released")

	screen.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and `ui_cancel`

## is DECLINED so the stack pops exactly as it pops every other screen. A screen that

## swallowed cancel would trap the player on a page with four verbs.


func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	var screen := _screen()

	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)

	screen.on_screen_shown()

	screen.on_screen_hidden()

	screen.focus_initial()

	assert_eq(screen.summary(), {}, "still empty, so a focus call did not invent state")

	screen.setup(_held[0])

	assert_eq(screen.on_stack_input(null), false, "a null event is declined")

	var cancel := InputEventAction.new()

	cancel.action = &"ui_cancel"

	cancel.pressed = true

	assert_eq(screen.on_stack_input(cancel), false, "cancel is declined so the stack pops")

	var right := InputEventAction.new()

	right.action = &"ui_right"

	right.pressed = true

	assert_eq(screen.on_stack_input(right), false, "and so is everything else")

	screen.free()


## `{}` is the row's FIRST state: a spare row in the pool that no claim occupies is not

## the same thing as a claim that was released, and a collapsed row would throw the

## distinction away.


func test_the_row_keeps_a_released_claim_apart_from_a_spare_pool_row() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as CustodyClaimRow

	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")

	assert_eq(row.is_filled(), false, "and is not filled")

	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"kind": "actor", "id": "warden"},
				"term_id": "custody",
				"periods": 3,
				"opened_period": 12,
				"status": "held",
			}
		)
	)

	assert_eq(row.is_filled(), true, "an authored claim fills it")

	assert_eq(row.is_held(), true, "and is held")

	assert_eq(row.is_vacant(), false, "with a holder, so not vacant")

	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"vacant": true},
				"term_id": "custody",
				"periods": 3,
				"opened_period": 12,
				"status": "released",
			}
		)
	)

	assert_eq(row.is_released(), true, "a released claim says so")

	assert_eq(row.is_vacant(), true, "and its holder is vacant, not absent")

	assert_eq(row.is_filled(), true, "and the row is STILL filled: the claim exists")

	assert_ne(
		String(row.summary()["card_tone"]),
		"ClaimCard",
		"on a different card, so the two never read alike"
	)

	row.clear()

	assert_eq(row.summary(), {}, "and clearing empties it again, rather than blanks")

	row.free()


# --- the panel owns every format ---------------------------------------------

## AGENTS.md: "no number formatting in a screen — the panel owns `%d/%d`, decimals and

## widths." So the row's rendered term line carries the figures and the SCREEN's summary

## carries them raw.


func test_the_row_panel_prints_the_figures_and_the_screen_formats_none() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as CustodyClaimRow

	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"kind": "sect", "id": "iron_vine"},
				"term_id": "custody",
				"periods": 6,
				"opened_period": 12,
				"status": "held",
			}
		)
	)

	var shown := row.summary()

	var term := String(shown["term_line"])

	# `str`, not `String(int)`: Godot 4.7 has no `String` constructor taking an int,

	# and the figure has to be the one the row printed, so it is rendered the same way.

	assert_ne(
		term.find(str(int(shown["periods"]))),
		-1,
		"the row prints the periods, which the record authored rather than the screen"
	)

	assert_ne(term.find("6"), -1, "and the authored six specifically")

	assert_ne(
		term.find(String(shown["term_id"])),
		-1,
		"and the term id, so a player reads what they are owed before pressing"
	)

	assert_ne(
		String(shown["holder_line"]).find("iron_vine"),
		-1,
		"and the holder's id, which is the only name on this row"
	)

	row.free()


# --- the boundaries, read off the SHIPPED source ------------------------------

## ## ## ADR 0104's load-bearing rule, machine-checked

##

## "A custody record has NO `description`, no `flavor`, and no `display_name`… prose in

## a save schema is how prose becomes what gets read." The FACADE already asserts this

## for the record; this is the half that was open — that the SURFACE does not grow a

## prose field either. A row that printed the subject's name beside the def id would be

## a second copy of it in the one place that has no authorization to author it, and no

## facade assertion could see that.

##

## Read as CODE, for the reason the scan in `test_forage_surface` gives: both files

## DOCUMENT the fields they are barred from, in the very sentences that forbid them, so

## a raw text scan would assert the comment and fail on the boundary it was written to

## prove.


func test_the_screen_invents_no_prose_field_over_the_custody_record() -> void:
	for path in [SCRIPT_PATH, PANEL_SCRIPT_PATH]:
		var code := _code_only(path)

		for forbidden in ['"description"', '"flavor"', '"display_name"', '"note"', '"note_"']:
			assert_eq(
				code.contains(forbidden),
				false,
				(
					"%s authors a prose field the ADR 0104 record does not carry: %s"
					% [path.get_file(), forbidden]
				)
			)

	# And the CONVERSE, which is the half a prohibition cannot state on its own: the

	# subject is named by its DEF ID and by nothing else. The row reads

	# `subject_id` and falls back to a constant of its own, so a name field could only

	# arrive as an id the row resolved — and `npc` is not in `UI_MODULES`, so there is

	# no catalog for this row to have resolved one through.

	assert_eq(
		_code_only(PANEL_SCRIPT_PATH).contains("subject_id"),
		true,
		"the row names a subject by the def id the claim carries"
	)

	for catalog in ["NpcDef", "NpcCatalog", "NpcApi", "npc/"]:
		assert_eq(
			_code_only(PANEL_SCRIPT_PATH).contains(catalog),
			false,
			(
				(
					"and the row names %s: the subject's name is authored on its def and read "
					% catalog
				)
				+ "through the catalog, which `ui/` may not reach"
			)
		)

	# The SCREEN may not reach it either, and the reason is sharper here than for a

	# node: a node's `display_name` arrives in `ForageApi.view`, whereas a custody record

	# carries NO name at all, so the screen has nothing to pass down even if it could.

	assert_eq(
		_code_only(SCRIPT_PATH).contains("NpcDef"),
		false,
		"the screen names no `NpcDef`: `custody` is in UI_MODULES with no module reach"
	)


## The screen names ONE facade and nothing else from `custody`, and no `app/` type.

## `tools arch` checks the module side of that boundary; this checks the UI side, by

## reading the shipped source.


func test_the_screen_names_one_facade_and_nothing_else_from_the_module() -> void:
	var code := _code_only(SCRIPT_PATH)

	# One call site per verb, so a screen that quietly re-implemented a verb beside the

	# facade's would be visible as a count rather than as a reading.

	for verb in ["CustodyApi.capture(", "CustodyApi.transfer(", "CustodyApi.release("]:
		assert_eq(code.count(verb), 1, "the screen calls %s by name, exactly once" % verb)

	assert_eq(
		code.count("CustodyApi.summary("),
		1,
		"and reads the facade once per refresh, so a refresh costs one call"
	)

	assert_eq(
		code.count("CustodyApi.settle_term("),
		1,
		"and settles a term through the facade rather than through a state interior"
	)

	# Module INTERIORS, and the app layer this program may not name at all.

	for interior in ["CustodyState", "CustodyWorldLedger", "EconomyApi", "EconomyValuation"]:
		assert_eq(
			code.contains(interior),
			false,
			(
				(
					"the screen names %s; ui/ may reach only the facade, and a custody term is "
					% interior
				)
				+ "never priced here"
			)
		)

	assert_eq(
		code.contains("EconomyBoot"),
		false,
		(
			"and no `app/` type: `app` is a PRIVATE_UNIT, so this screen has no seam and "
			+ "needs none"
		)
	)

	assert_eq(
		code.contains("res://src/modules/"),
		false,
		"and paths into no module; a panel calls the facade by bare name"
	)

	# The panel holds the same line: it renders a dictionary and reaches nothing.

	var panel := _code_only(PANEL_SCRIPT_PATH)

	for interior in ["CustodyApi", "CustodyState", "CustodyWorldLedger", "ActorFactory"]:
		assert_eq(
			panel.contains(interior),
			false,
			"the row names %s either; it renders a dictionary and reaches nothing" % interior
		)

	# `OwnerRef` is a CONTRACT, not a module interior: `ui` may depend on `core` and

	# `contracts`, so reading the vacancy marker off a holder ref is legal and is the

	# only reason a released claim and a spare pool row can look different.

	assert_eq(
		panel.contains("OwnerRef.is_vacant("),
		true,
		"and the row may read `OwnerRef`, which is the one contract this page leans on"
	)


## The route is REACHABLE, not merely shippable, and the REAL `ScreenRoutes` API is

## what answers. There is no `route_for_scene`: the table is keyed by id, so the claim

## is read the way the shell reads it — `id_for_scene` for the seam back, `scene_of`

## for the load, `action_of` for the key.


func test_the_custody_route_is_published_and_bound_to_a_key() -> void:
	assert_eq(
		ScreenRoutes.id_for_scene(String(SCREEN_SCENE.resource_path)),
		ROUTE,
		"the route table mounts this scene, and names it by id"
	)

	assert_eq(ScreenRoutes.has(ROUTE), true, "and the id is in the table")

	assert_eq(
		ScreenRoutes.scene_of(ROUTE),
		String(SCREEN_SCENE.resource_path),
		"and the route and the loaded scene are the same file, in both directions"
	)

	assert_eq(
		ScreenRoutes.node_of(ROUTE),
		"CustodyScreen",
		"and the mounted node says which route it is in"
	)

	assert_eq(
		SCREEN_SCENE.can_instantiate(),
		true,
		"so the path the table names is a scene that actually loads"
	)

	var action := ScreenRoutes.action_of(ROUTE)

	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")

	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action routes back to this route, so no key can open another screen"
	)

	# And the key is this route's OWN: a shared key is a route a keyboard player can

	# only reach by accident.

	for other in ScreenRoutes.ids():
		if other == ROUTE:
			continue

		assert_ne(
			ScreenRoutes.action_of(other), action, "no other route shares this route's input action"
		)


## ## The route is BOUND — and ADR 0247 gave it ONE seam, for the subject list alone

##

## This is the claim `ForageScreen` could not make: custody needs no injected `Callable`

## for any of its four VERBS, because `rules.UI_MODULES` grants `custody` with no module

## reach and every verb takes primitives plus the actor the screen already holds.

##
## That is still true and is still asserted below. What changed is that the page could not

## FIRE: DEF-0310 found `stage_capture` with no production caller, so the capture control

## was permanently disabled and the primary verb was unreachable. ADR 0247 decided what

## produces a claim and added exactly one thing the root must hand over — the LIST of

## capturable individuals, which `npc` owns and `ui/` may not name. So the route has an

## arm of its own now, and the claim is NARROWER and STRONGER than the one it replaced:

## the four verbs need no seam, the subject list does, and the arm opens that one door.


func test_the_composition_root_binds_the_custody_route_through_its_one_seam() -> void:
	# Read CODE, not the file: `item_workbench_app.gd` documents this program at

	# length in docstrings that name `ForageScreen` and `bind_harvest` too, so a raw

	# text scan would be asserting the comment. `_code_only` strips them first.

	# BOTH files of the root: the custody ARM and `_capturable_cast` moved to its routes
	# half when the app hit gdlint's line ceiling, and the claim is about the pair.
	var source := (
		_code_only("res://src/app/item_workbench_app.gd")
		+ _code_only("res://src/app/item_workbench_routes.gd")
	)

	assert_ne(source.is_empty(), true, "the composition root's source is readable")

	# ADR 0247's arm, asserted as a CALL SITE rather than as the absence of an arm. The
	# old assertion was "the root declares no custody arm", which could only fail if a
	# future agent added the wrong code — and a test that the right edit cannot fail is
	# not a test. This one fails if the arm is deleted, renamed, or pointed at nothing.

	assert_eq(
		source.contains('screen.call("bind_capture_options", _capturable_cast)'),
		true,
		(
			"the root hands the page the capturable list, and the call is on a NAMED method - "
			+ "an inline lambda calling another script's static is the access-violation shape "
			+ "every other seam in this file documents"
		)
	)
	assert_eq(
		source.contains("func _capturable_cast() -> Array:"),
		true,
		"and that method exists, so the binding resolves to something"
	)

	assert_eq(
		source.contains("ROUTE_CUSTODY:"),
		true,
		"on an arm of its own, because the subject list has to come from somewhere"
	)

	# Still `setup(actor)` beside it: the four custody VERBS reach `CustodyApi` by bare
	# name and need nothing injected, and that is the property this route was shipped to
	# prove — one seam must not have eroded it into a pure consumer.

	# And the screen takes exactly ONE seam: a `bind_*` method nothing opens would be a
	# door with no key, which is the fight page's original defect in reverse.

	for seam in ["bind_custody", "bind_harvest", "bind_quests", "bind_fight"]:
		assert_eq(
			(screen_method_names() as Array).has(seam),
			false,
			"the screen publishes no %s(): nothing opens that door" % seam
		)


## ## The last three bans, read off the SHIPPED screen

##

## No `queue_free()` — a deferred free never runs under a runner driven from

## `SceneTree._initialize()`, so it leaks a screen's whole row pool for the life of the

## process. No `theme_override_*`. No `@onready`. And no number formatting of its own.

##

## ## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`

##

## The rule is "no number formatting in a screen — the panel owns `%d/%d`", and what it

## protects is the FIGURES A PLAYER READS. The screen may still name a count it does

## not display: it grows its row pool with `row.name = "Claim%d"`, and a node's name in

## the scene tree is not an authored figure on a card. So the scan looks for a format in

## the same expression as an assignment to something a `Label` reads.


func test_the_screen_breaks_none_of_the_three_bans_the_ui_standard_states() -> void:
	var code := _code_only(SCRIPT_PATH)

	assert_eq(code.contains("queue_free"), false, "no queue_free(): the runner never defers")

	assert_eq(code.contains("theme_override_"), false, "no theme_override_*: the theme owns style")

	assert_eq(code.contains("@onready"), false, "no @onready: nodes resolve in _bind_nodes()")

	assert_eq(code.contains("func _bind_nodes()"), true, "which this screen declares")

	for sink in [".text =", "rates_line", "term_line", "subject_line", "holder_line"]:
		for format in ["%d", "%.1f", "%.2f"]:
			var line := ""

			for candidate in code.split("\n"):
				if candidate.contains(sink) and candidate.contains(format):
					line = candidate

					break

			assert_eq(
				line.is_empty(),
				true,
				"no formatted figure reaches a label: %s (%s)" % [sink, format]
			)

	# The pool grows; it never mints a control the scene did not mount. `RowBudget` and

	# `ActionSet` are the two things a screen legitimately grows and delegates to.

	assert_eq(code.count("instantiate()"), 2, "it grows rows and only rows")


## The panel holds the same line, for the reason `test_forage_surface` gives: the runner

## drives it with no scene tree, so a widget bound in `@onready` is never bound.


func test_the_row_binds_its_nodes_lazily_and_builds_no_widgets_in_ready() -> void:
	var code := _code_only(PANEL_SCRIPT_PATH)

	assert_eq(code.contains("@onready"), false, "no @onready in a panel")

	assert_eq(code.contains("func _bind_nodes()"), true, "it binds in _bind_nodes()")

	assert_eq(code.contains(".new()"), false, "and mints no widget, which a scene mounts")

	assert_eq(code.contains("queue_free"), false, "and never defers a free")


## The scene itself is composed: anchors and Containers only, and styled through

## `theme_type_variation` rather than a `theme_override_*`. Read from the SHIPPED scene

## rather than asserted about the script, because a `.tscn` is where a stray

## `position = Vector2(…)` would live and a script scan cannot see it.


func test_the_scene_is_anchors_and_containers_only() -> void:
	var scene := FileAccess.get_file_as_string(String(SCREEN_SCENE.resource_path))

	assert_ne(scene.is_empty(), true, "the screen scene is readable")

	assert_eq(scene.contains("theme_override"), false, "the scene styles by variation only")

	assert_eq(scene.contains("anchors_preset"), true, "and the root is anchored")

	for banned in ["position = Vector2", "offset_left", "offset_top"]:
		assert_eq(
			scene.contains(banned), false, "the scene declares no absolute geometry: %s" % banned
		)

	# The panel scene too, since it is a second shipped surface.

	var row_scene := FileAccess.get_file_as_string(String(ROW_SCENE.resource_path))

	assert_ne(row_scene.is_empty(), true, "the row scene is readable")

	assert_eq(row_scene.contains("theme_override"), false, "and it styles by variation only")
