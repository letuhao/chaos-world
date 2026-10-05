extends "res://tests/ui/floor_surface_fixture.gd"

## ## This file holds the PLAYER-FACING half of the floor surface suite
##
## DEF-0309: `MarketApi.drop`, `take` and `settle` shipped engine-complete and
## player-unreachable. A repo-wide grep found declarations and docstrings only, and
## `market_screen.gd` said in its own words that the floor was "deliberately NOT on
## this surface". So a dropped item was a ledger row a test could reach and a player
## could not: one hero put goods down, and nothing in the shipped program could pick
## them up again.
##
## Every case below drives the screen the way a player drives it and asserts the
## OUTCOME in the bag and on the floor — never widget existence. A screen that
## rendered a row and moved nothing would pass a "the button is enabled" assertion,
## and a screen that conjured goods would pass nothing else.
##
## The screen-contract and structural-pin half is `test_floor_surface_contract.gd`.

# --- the floor, end to end ----------------------------------------------------


## THE claim of the floor half. A player opens the page, a drop someone else left
## RENDERS, and taking it moves the goods out of the floor and into this hero's bag.
##
## Both halves are asserted because either alone is satisfiable by a lie: a screen
## that showed a row and took nothing would pass a rendering assertion, and a screen
## that conjured goods would pass nothing else. The goods are read off the BAG and the
## entry off the WORLD ledger, so the two sides cannot be satisfied by the same
## fiction.
func test_a_player_takes_a_drop_someone_else_left_and_the_goods_move_to_their_bag() -> void:
	var dropper := _carrier(&"the_dropper", 3)
	var dropped := MarketApi.drop(
		dropper, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 3}], 0
	)
	assert_eq(bool(dropped["ok"]), true, "setup: the rival left something: %s" % dropped["reason"])
	var drop_id := _only_drop_id()

	var taker := _hero(&"the_taker", 0)
	var screen := _floor(taker)
	assert_eq(
		(screen.summary()["drop_ids"] as Array).has(drop_id),
		true,
		"a drop another player left is a row on this page (ADR 0101: the floor is a world fact)"
	)
	var row := _row_for(screen, drop_id)
	assert_ne(row, {}, "the pick fills a row")
	assert_eq(String(row["def_id"]), String(GOOD), "and it is the good that was left")
	# The panel owns the format, so the row's OWN line carries the figure — which is
	# the half a number-only assertion cannot see.
	assert_ne(
		String(row["good_line"]).find("3"),
		-1,
		"the rendered line carries the quantity the take will deliver"
	)
	assert_ne(
		String(row["decay_line"]).find(FloorDropRow.NO_DECAY_TEXT),
		-1,
		"and an entry that never decays SAYS so, rather than printing a zero a player reads as an expiry"
	)
	assert_eq(bool(row["mine"]), false, "and the row knows this hero did not leave it")

	# The pick decides the entry: `act_take` refuses `no_drop_picked` on an empty pick
	# rather than silently acting on whichever row happens to be first, so a test that
	# never picked was measuring a refusal and then reading the refusal's dictionary as
	# a pickup.
	assert_eq(screen.select_drop(drop_id), true, "the drop is selectable")
	var floor_before := _floor_entries().size()
	var taken := screen.act_take()
	assert_eq(bool(taken["ok"]), true, "the take runs: %s" % taken["reason"])
	assert_eq(int(taken["quantity"]), 3, "and the verdict carries the quantity it delivered")
	assert_eq(
		ItemsApi.inventory(taker).count(GOOD),
		3,
		"the goods are really in this hero's bag, not merely absent from the floor"
	)
	assert_eq(
		_floor_entries().size(),
		floor_before - 1,
		"and the entry is really gone from the floor, not re-listed on the next refresh"
	)
	assert_eq(
		ItemsApi.inventory(dropper).count(GOOD),
		0,
		"while the dropper's own copy is gone too: the goods moved, they were not copied"
	)
	assert_eq((screen.summary()["drop_ids"] as Array).has(drop_id), false, "and the row is gone")
	screen.free()


## The other direction. A player puts goods down and the world says so — the floor is
## not this hero's private list, so the entry names them as its author.
func test_a_player_drops_from_their_bag_and_the_floor_names_them_as_its_author() -> void:
	var hero := _carrier(&"the_giver", 2)
	assert_eq(ItemsApi.inventory(hero).count(GOOD), 2, "setup: the hero carries the good")
	var screen := _floor(hero)

	var dropped := screen.act_drop(String(GOOD), 2, 0)
	assert_eq(bool(dropped["ok"]), true, "the drop runs: %s" % dropped["reason"])
	assert_eq(
		ItemsApi.inventory(hero).count(GOOD), 0, "and the goods LEFT the bag, not a copy of them"
	)
	var drop_id := _only_drop_id()
	var entry := _entry(drop_id)
	assert_ne(entry, {}, "the world holds the entry")
	assert_eq(int(entry["quantity"]), 2, "with the quantity that was left")
	assert_eq(String(entry["dropped_by"]), String(hero.id), "authored by the hero who left it")

	# And it is on THIS page, from the hero's own point of view, as a row that says so.
	var row := _row_for(screen, drop_id)
	assert_ne(row, {}, "the drop is a row on the page")
	assert_eq(bool(row["mine"]), true, "and the row knows this hero left it")
	assert_ne(
		String(row["by_line"]).find(String(hero.id)),
		-1,
		"the row PRINTS who left it, so a shared floor says whose goods these are"
	)
	screen.free()


## The AGING verb, which is the whole reason `market_screen.gd` said the floor was
## deliberately absent: nothing owns a clock, so an entry whose `decay_periods` has
## elapsed is destroyed by a caller that passes `periods`. Asserted from BOTH sides —
## the row before the press and the ledger after it.
func test_the_settle_verb_destroys_an_entry_whose_decay_has_elapsed_and_keeps_the_rest() -> void:
	var hero := _carrier(&"the_tidier", 5)
	# Two drops at one location: one that rots, one that never does. Only the first is
	# given a decay, because `MarketApi.drop` authors `decay_periods` AT DROP TIME and a
	# write-through patch afterwards reads as having worked and has not.
	assert_eq(
		bool(
			MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 2}], 2)["ok"]
		),
		true,
		"setup: a rotting drop"
	)
	assert_eq(
		bool(
			MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 0)["ok"]
		),
		true,
		"setup: a drop that never rots"
	)
	assert_eq(_floor_entries().size(), 2, "setup: two entries lie on the floor")

	var screen := _floor(hero)
	var rows := screen.summary()["rows"] as Array
	assert_eq(rows.size(), 2, "both are rows on the page")
	assert_eq(_count_where(rows, "decaying"), 1, "and exactly one of them is on a clock")
	var rotting := _rotting_row(screen)
	assert_ne(rotting, {}, "the rotting entry is a row")
	assert_eq(int(rotting["periods_left"]), 2, "with its whole window ahead of it")

	# One period is not enough: the window is 2, and a settle that destroyed it early
	# would be the floor destroying goods a player could still have claimed.
	var first := screen.act_settle(1)
	assert_eq(bool(first["ok"]), true, "the first period settles: %s" % first["reason"])
	assert_eq(int(first["expired"]), 0, "and destroys nothing yet")
	assert_eq(int(first["remaining"]), 2, "because both entries are still on the floor")
	assert_eq(
		int(_row_for(screen, String(rotting["drop_id"]))["periods_held"]),
		1,
		"and the rotting entry's own row shows the period it has been held"
	)

	# The second period elapses its window and the entry is GONE — goods destroyed,
	# which is what makes the floor the only container in this program that destroys on
	# expiry, and what `loot`'s stash deliberately is not.
	var second := screen.act_settle(1)
	assert_eq(bool(second["ok"]), true, "the second period settles")
	assert_eq(int(second["expired"]), 1, "and the rotting entry is destroyed")
	assert_eq(int(second["remaining"]), 1, "while the one that never decays stays")
	assert_eq(
		_row_for(screen, String(rotting["drop_id"])),
		{},
		"and the destroyed entry is no longer a row on the page"
	)
	assert_eq(
		ItemsApi.inventory(hero).count(GOOD),
		4,
		"and no goods came back to anyone: decay destroys rather than delivers"
	)
	assert_eq(
		_count_where(screen.summary()["rows"] as Array, "decaying"),
		0,
		"leaving a floor with nothing left on a clock"
	)
	screen.free()


## The floor is bounded per location, and the refusal is the MODULE's own id rather
## than a screen sentence. A screen that pre-judged the cap would refuse a drop the
## module would accept and report a reason nobody authored.
func test_a_full_floor_refuses_the_ninth_drop_by_the_module_own_name() -> void:
	var hero := _carrier(&"the_filler", 40)
	for index in range(MarketApi.MAX_FLOOR_PER_LOCATION):
		var placed := MarketApi.drop(
			hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 0
		)
		assert_eq(bool(placed["ok"]), true, "setup: drop %d is admitted" % index)
	assert_eq(
		_floor_entries().size(),
		MarketApi.MAX_FLOOR_PER_LOCATION,
		"setup: the floor is at the module's own per-location cap"
	)
	var screen := _floor(hero)
	var dropped := screen.act_drop(String(GOOD), 1, 0)
	assert_eq(
		bool(dropped["ok"]),
		false,
		"a ninth entry is refused: a floor that grew would be a save that grew"
	)
	assert_eq(
		String(dropped["reason"]),
		MarketApi.FLOOR_FULL,
		"and the refusal is the module's own id, passed through by name"
	)
	assert_eq(
		ItemsApi.inventory(hero).count(GOOD),
		40 - MarketApi.MAX_FLOOR_PER_LOCATION,
		"and the refused drop took nothing: a refusal writes nothing on either side"
	)
	screen.free()


## A take with nothing picked is refused BY NAME, distinct from every module refusal:
## there IS an entry and there IS a floor, and this screen was not told which one.
func test_a_take_with_no_pick_refuses_no_drop_picked_and_leaves_the_floor_alone() -> void:
	var hero := _carrier(&"the_indecisive", 1)
	var placed := MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 0)
	assert_eq(bool(placed["ok"]), true, "setup: an entry lies on the floor")
	var screen := _floor(hero)
	var taken := screen.act_take()
	assert_eq(bool(taken["ok"]), false, "so a take with no pick cannot run")
	assert_eq(
		String(taken["reason"]),
		FloorScreen.NO_DROP_PICKED,
		"and the refusal names the missing pick rather than reporting a pickup nobody made"
	)
	assert_eq(
		bool((screen.summary()["enabled"])["take"]),
		false,
		"and the control is DEAD, rather than live and refusing on every press"
	)
	assert_eq(_floor_entries().size(), 1, "while the entry is exactly where it was")
	screen.free()


## A screen at no location says so, which is a different sentence from "the floor is
## empty". The first says nobody named a room; the second says the room is bare.
func test_a_floor_with_no_location_names_no_location_rather_than_listing_everywhere() -> void:
	var dropper := _carrier(&"a_dropper", 1)
	MarketApi.drop(dropper, SHOP_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 0)
	var hero := _hero(&"nowhere", 0)
	var screen := (FLOOR_SCENE as PackedScene).instantiate() as FloorScreen
	screen.setup(hero)
	# Explicitly typed, not `:=`: a `Dictionary` subscript is a `Variant`, and inferring
	# from one is a parse error in this repo.
	var located: Variant = screen.summary()["located"]
	assert_eq(
		bool(located),
		false,
		(
			"nothing was named, so nothing is located; the key is a BOOLEAN, so `String()` "
			+ "on it would read 'false' as a location id"
		)
	)
	assert_eq(
		(screen.summary()["drop_ids"] as Array).size(),
		0,
		"and a drop lying in a DIFFERENT room is not listed: a defaulted location would be a floor that is everywhere"
	)
	var taken := screen.act_take(_only_drop_id_at(SHOP_LOCATION))
	assert_eq(String(taken["reason"]), FloorScreen.NO_LOCATION, "and the refusal says so")
	screen.free()


## Nothing a player can press invents time (DEF-0111). Zero periods is refused by the
## module's own id rather than silently treating "no time passed" as "everything rotted".
func test_a_settle_of_zero_periods_is_refused_rather_than_aging_the_whole_floor() -> void:
	var hero := _carrier(&"the_impatient", 1)
	MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 1)
	var screen := _floor(hero)
	var settled := screen.act_settle(0)
	assert_eq(bool(settled["ok"]), false, "zero periods cannot settle")
	assert_eq(
		String(settled["reason"]),
		MarketApi.NO_PERIODS,
		"and the refusal is the module's own id, so one name covers the whole path"
	)
	assert_eq(
		int(_entry(_only_drop_id())["periods_held"]),
		0,
		"and nothing was aged: a verb handed no time ages nothing"
	)
	screen.free()


## One key walks the shown list and takes what is picked, and each is consumed only
## when it did something — so `ui_cancel` stays free for `ScreenStack` to pop.
func test_the_pick_walks_the_shown_list_and_accept_takes_the_picked_drop() -> void:
	var hero := _carrier(&"keyboard", 3)
	MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 1}], 0)
	MarketApi.drop(hero, FLOOR_LOCATION, [{"def_id": String(GOOD), "quantity": 2}], 0)
	var screen := _floor(hero)
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_eq(screen.on_stack_input(down), true, "down picks the first drop")
	var picked := String(screen.summary()["selected_drop"])
	assert_ne(picked, "", "and something is picked")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(screen.on_stack_input(accept), true, "accept is consumed, because it took something")
	assert_eq(bool(screen.summary()["last_ok"]), true, "and the take is published as primitives")
	assert_eq(
		int(screen.summary()["last_quantity"]),
		1,
		"naming the quantity that moved, so the page says how much came off the floor"
	)
	screen.free()


# --- helpers on this suite ---------------------------------------------------


## The floor's one entry id, or `""` so a broken fixture turns the NEXT assertion red
## with a message rather than aborting this one halfway through.
func _only_drop_id() -> String:
	return _only_drop_id_at(FLOOR_LOCATION)


func _only_drop_id_at(location: StringName) -> String:
	var entries := _floor_entries(location)
	assert_eq(entries.size(), 1, "the fixture left exactly one entry on the floor")
	return String((entries[0] as Dictionary).get("drop_id", "")) if entries.size() == 1 else ""


## The one row on the page that is on a clock, or `{}`.
func _rotting_row(screen: FloorScreen) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if bool((row as Dictionary).get("decaying", false)):
			return row as Dictionary
	return {}
