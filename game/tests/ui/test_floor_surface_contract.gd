extends "res://tests/ui/floor_surface_fixture.gd"

## ## This file holds the SCREEN-CONTRACT and STRUCTURAL-PIN half of the floor surface
##
## What a routed screen may and may not SAY, and what it may not reach for: the summary
## is primitives only, the `ScreenStack` hooks are safe with nothing bound, the row
## resolves its widgets lazily, the route is published and bound to a key, and the
## screen names no `app/` type and no module interior.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Every scene preload, path constant, fixture and helper the
## cases use lives in `floor_surface_fixture.gd`, which both halves `extends`.
##
## `setup()` / `teardown()` live in that base, because `MarketApi.set_store` is
## PROCESS-WIDE: state installed by one half and cleared by the other outlives the
## suite and is inherited by everything that runs later.
##
## The player-facing half is `test_floor_surface.gd`.

# --- the screen contract -----------------------------------------------------


## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state
## unreadable rather than merely empty.
func test_the_floor_summary_is_empty_without_an_actor() -> void:
	var screen := (FLOOR_SCENE as PackedScene).instantiate() as FloorScreen
	assert_eq(screen.summary(), {}, "the floor reports nothing, not keys, with no hero")
	screen.free()


## `summary()` is PRIMITIVES ONLY, with each row's own summary nested under that row's
## key. A `Node`, `Resource` or `Object` in a summary is how a testable surface quietly
## stops being testable.
func test_the_floor_summary_is_primitives_only_with_nested_rows() -> void:
	var hero := _carrier(&"reader", 2)
	MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 2}], 3)
	var screen := _floor(hero)
	var reported := screen.summary()
	assert_ne(reported.is_empty(), true, "the floor has something to report")
	# `str` over the ARRAY, not `"%s" % offenders`: Godot's `%` on an Array UNPACKS it as
	# the format argument list, so a single `%s` against a two-element array is "not
	# enough arguments for format string" — a runtime error, not a red assertion.
	var offenders := _non_primitives(reported, "")
	var offenders_text := str(offenders)
	assert_eq(
		offenders.is_empty(), true, "the floor summary holds only primitives: %s" % offenders_text
	)
	var rows := reported["rows"] as Array
	assert_ne(rows.is_empty(), true, "and the drop's own summary is nested under 'rows'")
	assert_eq(
		_non_primitives(rows[0] as Dictionary, "rows[0]").is_empty(),
		true,
		"including the realized instance payload the ledger carries behind it"
	)
	screen.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and
## `ui_cancel` is DECLINED so the stack pops exactly as it pops every other screen. A
## screen that swallowed cancel would trap the player on a page that has verbs.
func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	for scene in [FLOOR_SCENE]:
		var screen := (scene as PackedScene).instantiate()
		for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
			assert_eq(screen.has_method(hook), true, "%s implements %s" % [scene, hook])
		screen.on_screen_shown()
		screen.on_screen_hidden()
		screen.focus_initial()
		assert_eq(screen.call(&"summary"), {}, "still empty, so a focus call invented nothing")

		screen.call(&"setup", _carrier(&"hooked", 1))
		screen.call(&"at_location", FLOOR_LOCATION)
		assert_eq(screen.call(&"on_stack_input", null), false, "a null event is declined")
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		assert_eq(
			screen.call(&"on_stack_input", cancel), false, "cancel is declined so the stack pops"
		)
		var other := InputEventAction.new()
		other.action = &"ui_right"
		other.pressed = true
		assert_eq(screen.call(&"on_stack_input", other), false, "and so is everything else")
		screen.free()


## The row owns every number the player reads, and the screen formats none of them.
## Asserted from the SHIPPED source, because the row's OWN sentences are the claim and a
## number-only assertion cannot see them.
func test_the_drop_row_prints_the_figures_and_the_screen_formats_none() -> void:
	var row := (DROP_ROW_SCENE as PackedScene).instantiate() as FloorDropRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	(
		row
		. show_drop(
			{
				"drop_id": "drop_0_alchemy_mist_herb",
				"location_id": String(FLOOR_LOCATION),
				"def_id": String(GOOD),
				"quantity": 7,
				"dropped_by": "a_rival",
				"periods_held": 2,
				"decay_periods": 5,
				"mine": false,
			}
		)
	)
	var shown := row.summary()
	assert_ne(shown, {}, "a drop fills it")
	assert_ne(
		String(shown["good_line"]).find("7"),
		-1,
		"the row prints the quantity the take will deliver"
	)
	assert_ne(String(shown["decay_line"]).find("2"), -1, "and how long the entry has been held")
	assert_ne(
		String(shown["decay_line"]).find("5"),
		-1,
		"and how long it lasts — the clock nothing else in this program renders"
	)
	assert_ne(
		String(shown["by_line"]).find("a_rival"),
		-1,
		"and who left it, which is the only fact a shared floor carries about ownership"
	)
	assert_eq(int(shown["periods_left"]), 3, "and the time remaining, read not derived")
	# An entry that never decays is a different sentence, not the same one with a zero.
	(
		row
		. show_drop(
			{
				"drop_id": "drop_1_alchemy_mist_herb",
				"def_id": String(GOOD),
				"quantity": 1,
				"decay_periods": 0,
				"periods_held": 0,
			}
		)
	)
	assert_eq(
		String(row.summary()["decay_line"]),
		FloorDropRow.NO_DECAY_TEXT,
		"an entry that never decays says so in words rather than printing an expiry"
	)
	assert_eq(
		int(row.summary()["periods_left"]),
		0,
		"and reports no time left without claiming it expired"
	)
	row.free()


## The route is REACHABLE, not merely shippable. A screen the composition root never
## mounts is reachable by nothing but this file, which is the shape DEF-0309 found.
## Asserted with the REAL `ScreenRoutes` API — keyed by id, with `id_for_scene` as the
## inverse (there is no `route_for_scene`).
func test_the_floor_route_is_published_and_bound_to_a_key() -> void:
	var scene := FLOOR_SCENE as PackedScene
	assert_eq(
		ScreenRoutes.id_for_scene(String(scene.resource_path)),
		FLOOR_ROUTE,
		"the route table mounts %s, and names it by id" % scene.resource_path
	)
	assert_eq(ScreenRoutes.has(FLOOR_ROUTE), true, "and '%s' is in the table" % FLOOR_ROUTE)
	assert_eq(
		ScreenRoutes.scene_of(FLOOR_ROUTE),
		String(scene.resource_path),
		"and the route and the loaded scene are the same file, in both directions"
	)
	assert_eq(scene.can_instantiate(), true, "so the path the table names loads")
	assert_ne(ScreenRoutes.node_of(FLOOR_ROUTE), "", "and the mounted node carries a name")
	var action := ScreenRoutes.action_of(FLOOR_ROUTE)
	assert_eq(InputMap.has_action(action), true, "and '%s' is declared in project.godot" % action)
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(FLOOR_ROUTE),
		"and the action routes back to this route, so no key can open another screen"
	)
	for other in ScreenRoutes.ids():
		if other == FLOOR_ROUTE:
			continue
		assert_ne(
			ScreenRoutes.action_of(other),
			action,
			"no other route shares this route's input action, or a keyboard player would reach the wrong screen"
		)


## And the page is BOUND by the composition root. A route whose arm was deleted would
## mount a screen with no location — every row empty, every verb refusing `no_location`,
## and every other case in this file measuring a board nobody opened.
##
## Read CODE, not the file: `item_workbench_app.gd` documents its routes at length in
## docstrings that name the seams too, so a raw text scan would be asserting the comment
## rather than the wiring. Every scan goes through `_code_only`, for the reason
## `test_forage_surface.gd` strips comments before looking for `@onready`.
func test_the_binding_arm_opens_the_floor_route_and_names_the_verbs() -> void:
	var source := _code_only(ROOT_SCRIPT_PATH)
	assert_ne(source.is_empty(), true, "the composition root's source is readable")
	assert_eq(source.count("ROUTE_FLOOR:"), 1, "the root binds the floor route exactly once")
	# The arm is the PLAIN default plus the location: every floor verb takes the bound
	# actor and plain ids, so there is NO seam to inject and a Callable wrapping a facade
	# call would be the ceremony this screen exists to avoid.
	assert_eq(
		source.count('"at_location", _market_location()'), 1, "and it hands the screen a location"
	)
	assert_eq(
		source.contains('screen.call("bind_floor"'),
		false,
		"and injects no seam: `market` is a granted facade, so the verbs are reached by name"
	)
	# The screens may not name any of it: `app/` is a `PRIVATE_UNIT`, so a seam is the
	# only door — and this route needs no door.
	for path in [FLOOR_SCRIPT_PATH, DROP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		for forbidden in ["ShopCounter", "AuctionBids", "NpcBoot", "res://src/app/"]:
			assert_eq(
				code.contains(forbidden),
				false,
				"%s names %s; ui/ may not name an app/ type" % [path, forbidden]
			)


## The screen reaches the floor by BARE NAME, because `market` is declared in
## `rules.UI_MODULES` and every argument of all three verbs is either the bound actor or
## a plain id. This is the claim custody makes about itself, asserted of the floor too:
## a route whose verbs are reachable by name needs no injected `Callable` at all.
func test_the_floor_screen_reaches_every_verb_by_name_and_injects_nothing() -> void:
	var code := _code_only(FLOOR_SCRIPT_PATH)
	for verb in ["MarketApi.drop(", "MarketApi.take(", "MarketApi.settle("]:
		assert_eq(code.count(verb), 1, "the screen calls %s exactly once, by name" % verb)
	assert_eq(
		code.count("MarketApi.summary(") >= 1,
		true,
		"and reads the facade's read model by name, exactly as the forage screen reads HoldingsApi"
	)
	assert_eq(
		code.contains("bind_floor(") or code.contains("Callable("),
		false,
		"the screen injects nothing: there is no `app/` type in the floor path to inject"
	)
	# And no `EconomyApi`: `economy` is the market MODULE's declared dependency, not a
	# grant to `ui/`.
	for path in [FLOOR_SCRIPT_PATH, DROP_ROW_SCRIPT_PATH]:
		assert_eq(
			_code_only(path).contains("EconomyApi"),
			false,
			(
				"%s names EconomyApi; `market: [economy]` is the module graph edge, not a ui/ grant"
				% path
			)
		)


## The screen names NO module interior and no path into a module; a panel calls the
## facade by bare name. `tools arch` checks the module side of that boundary; this
## checks the UI side, by reading the shipped source.
func test_the_floor_names_a_facade_and_nothing_else_from_the_market_module() -> void:
	for path in [FLOOR_SCRIPT_PATH, DROP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		for interior in [
			"MarketState",
			"MarketWorldLedger",
			"MarketTransfer",
			"MarketSpread",
			"AuctionReadModel",
			"EconomyValuation",
			"EconomyExchange",
		]:
			assert_eq(
				code.contains(interior),
				false,
				"%s names %s; ui/ may only reach the facade" % [path, interior]
			)
		assert_eq(
			code.contains("res://src/modules/"),
			false,
			"%s paths into no module; a screen calls the facade by bare name" % path
		)
	# The row is a row of the same data and names less than the screen does.
	var row := _code_only(DROP_ROW_SCRIPT_PATH)
	for interior in ["MarketApi", "MarketState", "ItemsApi"]:
		assert_eq(
			row.contains(interior),
			false,
			"the drop row names %s either; it renders a dictionary and reaches nothing" % interior
		)


## The panels must resolve their widgets lazily, never in `@onready`, or a headless run
## that drives them with no scene tree binds nothing and renders nothing.
##
## Read as code, for the reason the scan above gives: these files document the rule by
## naming the token, and a raw scan would fail on the very boundary it was written to
## prove.
func test_the_floor_resolves_its_nodes_lazily_and_builds_no_widgets_in_ready() -> void:
	for path in [FLOOR_SCRIPT_PATH, DROP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		assert_eq(code.contains("@onready"), false, "%s declares no @onready" % path)
		assert_eq(code.contains("func _bind_nodes()"), true, "%s binds in _bind_nodes()" % path)
		assert_eq(
			code.count("get_node_or_null(") > 0 and code.count(".new()") == 0,
			true,
			"%s resolves lazily and mints no widget, which a scene mounts" % path
		)


## The last three bans, read off the SHIPPED files: no `queue_free()` (a deferred free
## never runs under a runner driven from `SceneTree._initialize()`, so it leaks a
## screen's whole row pool for the life of the process), no `theme_override_*`, and no
## number formatting of its own in the SCREEN.
##
## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`
##
## The rule is "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths", and what it protects is the FIGURES A PLAYER READS. A screen may still name
## a count it does not display: it grows its row pool with `row.name = "Drop%d"`, and a
## node's name in the scene tree is not an authored figure on a card. So the scan looks
## for a format in the same expression as an assignment to something a `Label` reads,
## which is the only place a formatted number reaches a player.
func test_the_floor_breaks_none_of_the_three_bans_the_ui_standard_states() -> void:
	for path in [FLOOR_SCRIPT_PATH, DROP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		assert_eq(
			code.contains("queue_free"),
			false,
			"%s has no queue_free(): the runner never defers" % path
		)
		assert_eq(
			code.contains("theme_override_"), false, "%s styles itself; the theme owns style" % path
		)
		if path.ends_with("floor_screen.gd"):
			assert_eq(
				code.contains(".free()"), false, "%s frees nothing at all from a screen" % path
			)
		for sink in [".text =", "good_line", "decay_line", "by_line"]:
			for format in ["%d", "%.1f", "%.2f"]:
				var line := ""
				for candidate in code.split("\n"):
					if candidate.contains(sink) and candidate.contains(format):
						line = candidate
						break
				assert_eq(
					line.is_empty(),
					true,
					"no formatted figure reaches a label in %s: %s%s" % [path, sink, format]
				)
