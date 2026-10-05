extends "res://tests/ui/market_surface_fixture.gd"

## ## This file holds the SCREEN-CONTRACT and STRUCTURAL-PIN half of the market surface
##
## What a routed screen may and may not SAY, and what it may not reach for: the summaries
## are primitives only, the `ScreenStack` hooks are safe with nothing bound, the panels
## resolve their widgets lazily, both routes are published and reachable from the
## composition root, and neither screen names an `app/` type or a module interior.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every case below is the original body verbatim, and every scene preload,
## path constant, fixture and helper it uses lives in `market_surface_fixture.gd`, which
## both halves `extends`.
##
## `setup()` / `teardown()` and the fixtures live in that base, because `MarketApi.set_store`
## and the `ShopCounter` cache are PROCESS-WIDE: state installed by one half and cleared
## by the other outlives the suite and leaks a live `Actor` until the process exits.
##
## The player-facing half is `test_market_surface.gd`.

# --- the screen contract -----------------------------------------------------


## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state
## unreadable rather than merely empty. Both screens, because both are routed.
func test_both_screen_summaries_are_empty_without_an_actor() -> void:
	var market := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	assert_eq(market.summary(), {}, "the market reports nothing, not keys, with no hero")
	market.free()
	var auction := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	assert_eq(auction.summary(), {}, "and so does the auction")
	auction.free()


## `summary()` is PRIMITIVES ONLY, with each row's own summary nested under that row's
## key. A `Node`, `Resource` or `Object` in a summary is how a testable surface quietly
## stops being testable — and `ShopCounter.summary` embeds a whole `definition`, so
## this is the assertion that proves the screen FLATTENED it rather than passed it on.
func test_both_screen_summaries_are_primitives_only_with_nested_rows() -> void:
	_shop = _hero(&"reader", 4000)
	var market := _market(_shop)
	var reported := market.summary()
	assert_ne(reported.is_empty(), true, "the market has something to report")
	var offenders := _non_primitives(reported, "")
	# `str` over the ARRAY, not `"%s" % offenders`: Godot's `%` on an Array UNPACKS it
	# as the format argument list, so a single `%s` against a two-element array is
	# "not enough arguments for format string" — a runtime error, not a red assertion.
	var offenders_text := str(offenders)
	assert_eq(
		offenders.is_empty(), true, "the market summary holds only primitives: %s" % offenders_text
	)
	var rows := reported["rows"] as Array
	assert_ne(rows.is_empty(), true, "and each stall's own summary is nested under 'rows'")
	assert_eq(
		_non_primitives(rows[0] as Dictionary, "rows[0]").is_empty(),
		true,
		"including the row that carries the definition the facade embedded"
	)
	market.free()

	var bidder := _hero(&"auction_reader", BIDDER_PURSE)
	var auction := _auction(bidder)
	var read := auction.summary()
	assert_eq(_non_primitives(read, "").is_empty(), true, "and so does the auction's")
	auction.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and
## `ui_cancel` is DECLINED so the stack pops exactly as it pops every other screen. A
## screen that swallowed cancel would trap the player on a page that has verbs.
func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	for scene in [MARKET_SCENE, AUCTION_SCENE]:
		var screen := (scene as PackedScene).instantiate()
		for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
			assert_eq(screen.has_method(hook), true, "%s implements %s" % [scene, hook])
		screen.on_screen_shown()
		screen.on_screen_hidden()
		screen.focus_initial()
		assert_eq(screen.call(&"summary"), {}, "still empty, so a focus call invented nothing")

		screen.call(&"setup", _hero(&"hooked", 4000))
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


## `ui_down` walks the SHOWN list and consumes only when it did something, and
## `ui_accept` buys the picked stall. One key, and the panel re-rendering between the
## two is what makes it readable rather than a guess.
func test_the_pick_walks_the_shown_list_and_accept_buys_the_picked_stall() -> void:
	_shop = _hero(&"keyboard", 4000)
	var screen := _market(_shop)
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_eq(screen.on_stack_input(down), true, "down picks the first stall")
	var picked := String(screen.summary()["selected_shop"])
	assert_ne(picked, "", "and something is picked")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(
		screen.on_stack_input(accept), true, "accept is consumed, because it bought something"
	)
	var after := screen.summary()
	assert_eq(bool(after["last_ok"]), true, "and the trade is published as primitives")
	assert_ne(
		int(after["last_coins"]), 0, "naming the coins that moved, so the page says what cost"
	)
	screen.free()


## Every authored stall is priced by the ONE reader, and the row prints that price
## rather than one it composed. Read from the shelf the facade published, so the
## assertion is about the panel owning the format rather than about a literal.
func test_the_shop_row_prints_the_figures_and_the_screen_formats_none() -> void:
	_shop = _hero(&"reader", 4000)
	var row := (SHOP_ROW_SCENE as PackedScene).instantiate() as MarketRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	var line := _shelf_row(SHOP_ID, &"alchemy_mist_herb")
	assert_ne(line, {}, "setup: the reagent row is priced")
	(
		row
		. show_shop(
			{
				"shop_id": String(SHOP_ID),
				"display_name": "Reader",
				"kind": "trader",
				"buys": ["alchemy_mist_herb"],
				"ok": true,
				"can_buy": true,
				"shelf": [line],
				"purse": 12,
				"funding": 34,
			}
		)
	)
	var shown := row.summary()
	assert_ne(shown, {}, "a priced stall fills it")
	assert_ne(
		String(shown["shelf_line"]).find(str(int(line["coins"]))),
		-1,
		"the row prints the authored charge, which the facade authored rather than the screen"
	)
	assert_ne(
		String(shown["purse_line"]).find("12"),
		-1,
		"and the stall's own purse, so a player reads the margin before trading"
	)
	assert_eq(
		String(shown["afford_line"]).to_lower(),
		"you can afford the cheapest of these",
		(
			"and the affordability sentence, which is the panel's own. Lower-cased before "
			+ "comparison because `String.capitalize()` is sentence-case: it leaves the "
			+ "interior words lower and only raises the first letter"
		)
	)
	row.free()


## The lot row publishes the high bidder and prints them, which is the fact the whole
## auction surface exists for. Asserted on a SYNTHETIC row so the case is about the
## panel's rendering rather than about a particular module fixture.
func test_the_lot_row_prints_the_high_bidder_and_a_lot_with_none_says_so() -> void:
	var row := (LOT_ROW_SCENE as PackedScene).instantiate() as AuctionLotRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	(
		row
		. show_lot(
			{
				"lot_id": "lot_hero_stone",
				"def_id": String(AUCTION_GOOD),
				"seller_id": "someone_else",
				"rarity": "rare",
				"price": 100,
				"required_bid": 110,
				"high_bid": "a_rival",
				"high_bid_amount": 210,
				"bid_count": 1,
				"closes_after": 3,
				"status": AuctionScreen.STATUS_OPEN,
				"can_bid": true,
			}
		)
	)
	var shown := row.summary()
	assert_ne(shown, {}, "a lot fills it")
	assert_ne(
		String(shown["high_line"]).find("a_rival"),
		-1,
		"the row PRINTS the high bidder's name — the fact no other surface published"
	)
	assert_ne(String(shown["high_line"]).find("210"), -1, "and the amount they stand at")
	assert_ne(
		String(shown["state_line"]).find("110"),
		-1,
		"and what the next bid has to be, which is what a bidder reads before pressing"
	)
	# A lot nobody has bid on is a different sentence, not an empty name.
	(
		row
		. show_lot(
			{
				"lot_id": "lot_quiet",
				"def_id": String(AUCTION_GOOD),
				"status": AuctionScreen.STATUS_OPEN,
				"required_bid": 10,
			}
		)
	)
	assert_eq(
		String(row.summary()["high_line"]),
		"No bids yet",
		"an unbid lot says so in words rather than printing nothing"
	)
	row.free()


## The route is REACHABLE, not merely shippable, for BOTH surfaces. A screen the
## composition root never mounts is reachable by nothing but this file, which is the
## shape the audit found. Asserted with the REAL `ScreenRoutes` API — keyed by id, with
## `id_for_scene` as the inverse (there is no `route_for_scene`).
func test_both_routes_are_published_and_bound_to_a_key() -> void:
	for pair in [
		[MARKET_SCENE, MARKET_ROUTE],
		[AUCTION_SCENE, AUCTION_ROUTE],
	]:
		var scene := pair[0] as PackedScene
		var route := StringName(pair[1])
		assert_eq(
			ScreenRoutes.id_for_scene(String(scene.resource_path)),
			route,
			"the route table mounts %s, and names it by id" % scene.resource_path
		)
		assert_eq(ScreenRoutes.has(route), true, "and '%s' is in the table" % route)
		assert_eq(
			ScreenRoutes.scene_of(route),
			String(scene.resource_path),
			"and the route and the loaded scene are the same file, in both directions"
		)
		assert_eq(scene.can_instantiate(), true, "so the path the table names loads")
		assert_ne(ScreenRoutes.node_of(route), "", "and the mounted node carries a name")
		var action := ScreenRoutes.action_of(route)
		assert_eq(
			InputMap.has_action(action), true, "and '%s' is declared in project.godot" % action
		)
		assert_eq(
			String(ScreenRoutes.route_for_action(action)),
			String(route),
			"and the action routes back to this route, so no key can open another screen"
		)


## And the page is REACHABLE from the composition root: the binding arms inject the
## seams. An unwired screen would refuse `no_market_seam` / `no_auction_seam` forever
## and every other case in this file would be measuring a seam nobody injected.
##
## Read CODE, not the file: `item_workbench_app.gd` documents these routes at length in
## docstrings that name every seam too, so a raw text scan would be asserting the
## comment rather than the wiring. Every scan in this file goes through `_code_only`,
## for the same reason `test_forage_surface.gd` strips comments before looking for
## `@onready`.
func test_the_binding_arms_inject_the_seams_the_screens_cannot_reach_themselves() -> void:
	var source := _code_only(ROOT_SCRIPT_PATH)
	assert_ne(source.is_empty(), true, "the composition root's source is readable")
	assert_eq(source.count("ROUTE_MARKET:"), 1, "the root binds the market route exactly once")
	assert_eq(source.count("ROUTE_AUCTION:"), 1, "and the auction route exactly once")
	# The market seam is `ShopCounter.at_location` by bare static name, and the two
	# verbs by the root's own methods (which resolve a counter the screen may not mint).
	assert_eq(
		source.count('Callable(ShopCounter, "at_location")'),
		1,
		"and it hands the screen `ShopCounter.at_location` itself, not a re-implementation"
	)
	assert_eq(
		source.count('"_market_buy"'), 1, "plus the buy verb, resolved against the counter cache"
	)
	assert_eq(source.count('"_market_sell"'), 1, "and the sell verb, which also carries the def")
	# The auction seam is `AuctionBids.bid` by bare static name — the whole reason this
	# route is half a consumer and the other half is by-name.
	assert_eq(
		source.count('Callable(AuctionBids, "bid")'),
		1,
		"and it hands the screen `AuctionBids.bid` itself, so the appetite arithmetic has one home"
	)
	# And the screens may not name any of it: `app/` is a `PRIVATE_UNIT`, so the seams
	# are the only door. Asserted from the shipped source, because that is the boundary
	# this file is the proof of.
	for path in [MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH]:
		var code := _code_only(path)
		for forbidden in ["ShopCounter", "AuctionBids", "ForageAction", "res://src/app/"]:
			assert_eq(
				code.contains(forbidden),
				false,
				(
					"%s names %s; ui/ may not name an app/ type, so the seam is the only door"
					% [path, forbidden]
				)
			)


## The two surfaces reach `market` by exactly the two roads there are, and which is
## which is the design rather than an accident.
##
## `rules.UI_MODULES` declares `"market": ["economy"]`, so `ui/` may name `MarketApi`
## — `tools/arch/enforce.py` checks `dep in rules.UI_MODULES` against the MODULE the
## reference resolves to, and `economy` has no key there, so `EconomyApi` by name from
## `ui/` would be an UNDECLARED module. The auction screen therefore lists BY NAME and
## bids by SEAM; the market screen reads its purse by name and needs BOTH seams,
## because `MarketApi.buy(shop_actor, player, rows)` takes a merchant `Actor` only
## `ShopCounter` (an `app/` type) can mint.
func test_the_auction_screen_reaches_the_verbs_by_the_only_two_roads_there_are() -> void:
	var auction := _code_only(AUCTION_SCRIPT_PATH)
	assert_eq(
		auction.count("MarketApi.list("),
		1,
		"the screen escrows BY NAME: every argument is the bound actor and two plain ids"
	)
	assert_eq(
		auction.count("MarketApi.summary(") >= 1,
		true,
		"and reads the facade's read model by name, exactly as the forage screen reads HoldingsApi"
	)
	# No `EconomyApi` anywhere: `economy` is the market MODULE's declared dependency, not
	# a grant to `ui/`.
	for path in [
		MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH
	]:
		assert_eq(
			_code_only(path).contains("EconomyApi"),
			false,
			(
				"%s names EconomyApi; `market: [economy]` is the module graph edge, not a ui/ grant"
				% path
			)
		)
	# The market screen reaches no verb by name, and says why.
	var market := _code_only(MARKET_SCRIPT_PATH)
	assert_eq(
		market.contains("MarketApi.buy(") or market.contains("MarketApi.sell("),
		false,
		"the market screen names no market verb: both take a shop Actor only app/ can mint"
	)
	assert_eq(
		market.count("MarketApi.summary(") >= 1,
		true,
		"so it reads the one thing the facade CAN hand it — the purse"
	)


## The screens name NO module interior and no path into a module; a panel calls the
## facade by bare name. `tools arch` checks the module side of that boundary; this
## checks the UI side, by reading the shipped source.
func test_the_screens_name_facades_and_nothing_else_from_either_module() -> void:
	for path in [MARKET_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH]:
		var code := _code_only(path)
		for interior in [
			"MarketState",
			"ShopDef",
			"ShopCatalog",
			"AuctionReadModel",
			"MarketTransfer",
			"MarketSpread",
			"EconomyValuation",
			"MarketWorldLedger",
		]:
			assert_eq(
				code.contains(interior),
				false,
				"%s names %s; ui/ may only reach the facade" % [path, interior]
			)
		assert_eq(
			code.contains("res://src/modules/"),
			false,
			"%s paths into no module; a panel calls the facade by bare name" % path
		)
	# The lot row is a row of the same data and names less than the screen does.
	var lot_row := _code_only(LOT_ROW_SCRIPT_PATH)
	for interior in ["MarketApi", "AuctionReadModel", "AuctionState", "AuctionBids"]:
		assert_eq(
			lot_row.contains(interior),
			false,
			"the lot row names %s either; it renders a dictionary and reaches nothing" % interior
		)


## The panels must resolve their widgets lazily, never in `@onready`, or a headless
## run that drives them with no scene tree binds nothing and renders nothing.
##
## Read as code, for the reason the scan above gives: these panels document the rule by
## naming the token, and a raw scan would fail on the very boundary it was written to
## prove.
func test_the_rows_bind_their_nodes_lazily_and_build_no_widgets_in_ready() -> void:
	for path in [
		SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH, MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH
	]:
		var code := _code_only(path)
		assert_eq(code.contains("@onready"), false, "%s declares no @onready" % path)
		assert_eq(code.contains("func _bind_nodes()"), true, "%s binds in _bind_nodes()" % path)
		assert_eq(
			code.count("get_node_or_null(") > 0 and code.count(".new()") == 0,
			true,
			"%s resolves lazily and mints no widget, which a scene mounts" % path
		)


## The last three bans, read off the SHIPPED screens: no `queue_free()` (a deferred
## free never runs under a runner driven from `SceneTree._initialize()`, so it leaks a
## screen's whole row pool for the life of the process), no `theme_override_*`, and no
## number formatting of its own.
##
## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`
##
## The rule is "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths", and what it protects is the FIGURES A PLAYER READS. A screen may still name
## a count it does not display: it grows its row pool with `row.name = "Lot%d"`, and a
## node's name in the scene tree is not an authored figure on a card. So the scan looks
## for a format in the same expression as an assignment to something a `Label` reads,
## which is the only place a formatted number reaches a player.
func test_the_screens_break_none_of_the_three_bans_the_ui_standard_states() -> void:
	for path in [
		MARKET_SCRIPT_PATH, AUCTION_SCRIPT_PATH, SHOP_ROW_SCRIPT_PATH, LOT_ROW_SCRIPT_PATH
	]:
		var code := _code_only(path)
		assert_eq(
			code.contains("queue_free"),
			false,
			"%s has no queue_free(): the runner never defers" % path
		)
		assert_eq(
			code.contains("theme_override_"), false, "%s styles itself; the theme owns style" % path
		)
		if path.ends_with("market_screen.gd") or path.ends_with("auction_screen.gd"):
			assert_eq(
				code.contains(".free()"), false, "%s frees nothing at all from a screen" % path
			)
		for sink in [".text =", "afford_line", "shelf_line", "high_line", "state_line"]:
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
