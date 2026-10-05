extends "res://tests/ui/market_surface_fixture.gd"

## ## This file holds the PLAYER-FACING half of the market surface suite
##
## The two read models and the four verbs, driven the way a player drives them: a
## shopper buys off a stall's shelf and the goods and the coins both move, a seller
## hands a good the other way, a bidder lists a lot and the high bid is shown on it
## afterwards -- and every refusal is asserted by NAME, because the name is the contract
## a panel switches on.
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
## The screen-contract and structural-pin half is `test_market_surface_contract.gd`.

# --- the market, end to end --------------------------------------------------


## THE claim of the market half. A player opens the page, the stall's shelf RENDERS,
## and buying moves both goods and coins.
##
## Both halves are asserted because either alone is satisfiable by a lie: a screen
## that showed a row and wrote nothing would pass a "the button is enabled"
## assertion, and a screen that conjured items would pass nothing else. The goods are
## read off the BAG and the coins out of the module's own purse, so the two sides
## cannot be satisfied by the same fiction.
func test_a_player_buys_from_a_stalls_shelf_and_the_goods_and_coins_both_move() -> void:
	_shop = _hero(&"shopper", 4000)
	var screen := _market(_shop)

	# Beat one: the SHELF renders. Read off the row pool, not the facade, so what the
	# player can see and what the verb will act on cannot be two different worlds.
	var listed := screen.summary()["shop_ids"] as Array
	assert_ne(listed.is_empty(), true, "the authored stall has a row on the page")
	assert_eq(listed.has(String(SHOP_ID)), true, "and it is the stall the content authors here")
	var row := _row_for(screen, String(SHOP_ID))
	assert_ne(row, {}, "the picked stall fills a row")
	var shelf := _shelf_row(SHOP_ID, &"alchemy_mist_herb")
	assert_ne(shelf, {}, "setup: the shelf prices a herb the hero will buy")
	# The panel owns the format, so the row's OWN line carries the figures — which is
	# the half a number-only assertion cannot see.
	assert_ne(
		String(row["shelf_line"]).find(str(int(shelf["coins"]))),
		-1,
		"the rendered shelf line carries the charge the verb will settle"
	)
	assert_eq(bool(row["can_buy"]), true, "a 4000-coin purse reaches the reagent row")

	# Beat two: the BUY runs. 4000 coins, one line off the shelf.
	# The stall the verbs act on is the PICK, never the first row: `act_buy` refuses
	# `no_shop_picked` on an empty pick rather than silently acting on whichever row
	# happens to be first, so a test that never picked was measuring a refusal and then
	# reading the refusal's dictionary as a purchase.
	assert_eq(screen.select_shop(String(SHOP_ID)), true, "the stall is selectable")
	var counter := ShopCounter.counter(SHOP_ID)
	assert_ne(counter, null, "setup: the stall is realized, so it has a bag to sell from")
	var counter_before := ItemsApi.inventory(counter).count(StringName(shelf["def_id"]))
	assert_ne(counter_before, 0, "setup: the counter really holds the good this test buys away")
	var before := EconomyApi.purse(_shop)
	var bought := screen.act_buy(String(shelf["def_id"]))
	assert_eq(bool(bought["ok"]), true, "the purchase is accepted: %s" % bought["reason"])
	assert_eq(bought.has("coins"), true, "and the verdict carries a settlement figure")
	assert_eq(int(bought["coins"]), int(shelf["coins"]), "and it charges the shelf's own price")
	assert_eq(
		ItemsApi.has_item(_shop, StringName(shelf["def_id"]), int(shelf["quantity"])),
		true,
		"and the hero really holds %d of '%s'" % [int(shelf["quantity"]), shelf["def_id"]]
	)
	assert_eq(
		EconomyApi.purse(_shop),
		before - int(shelf["coins"]),
		"so the coins left the purse for exactly what the shelf charged"
	)
	# The counter and the world cannot both still have the goods, or the item exists
	# twice.
	#
	## ## What is asserted is the COUNTER's bag, and why neither other figure would do
	#
	# `ShopDef.stock` is the AUTHORED BASELINE the counter is realized from, and nothing
	# decrements it — so a stall whose stock entry is still 10 after a purchase has
	# answered nothing, and asserting it went to zero was measuring a `.tres` constant
	# rather than a transfer. The counter's summary is not the right place either:
	# `MarketApi.buy` escrows through `Inventory.remove_instance`, which removes a
	# realized INSTANCE, and a stackable the def authors is bought back as a fresh
	# realization in a NEW slot — so the summary still lists a `quantity` for a def
	# whose authored stack is gone.
	#
	# The fact ADR 0100 makes is "the goods leave the merchant", and the one reader of it
	# is `Inventory.count` on the COUNTER's own bag: it sums every slot carrying that
	# def id however the bag files it. Read BEFORE the trade and again after it, and the
	# difference is the claim. `ShopCounter.summary`'s `stock` is deliberately NOT the
	# figure: it lists one row PER STACK, and a realized instance bought back into a
	# fresh slot is a second row rather than a smaller first one.
	var bought_quantity := int(shelf["quantity"])
	assert_eq(
		ItemsApi.inventory(counter).count(StringName(shelf["def_id"])),
		counter_before - bought_quantity,
		"and the merchant holds exactly that much less: the goods LEAVE it (ADR 0100)"
	)
	screen.free()


## A sell is the other direction of the same counter, and it is refused by the SHOP's
## authored `buys` list rather than by anything the screen decided — which is what
## makes a black market a content choice rather than a price modifier.
func test_selling_to_a_stall_moves_the_goods_the_other_way() -> void:
	_shop = _hero(&"seller", 200)
	var herb := _instance(_shop, &"alchemy_mist_herb", &"herb_for_sale")
	assert_ne(herb, "", "setup: the hero holds a realized herb instance")
	var screen := _market(_shop)
	assert_eq(screen.select_shop(String(SHOP_ID)), true, "the stall is selectable")

	var before := EconomyApi.purse(_shop)
	var sold := screen.act_sell("alchemy_mist_herb", 1)
	assert_eq(
		bool(sold["ok"]), true, "the stall authors this herb on its buys list: %s" % sold["reason"]
	)
	assert_eq(
		ItemsApi.inventory(_shop).count(&"alchemy_mist_herb"), 0, "and the hero's copy is gone"
	)
	assert_eq(
		bool(EconomyApi.purse(_shop) > before),
		true,
		"and the stall paid more than nothing, which is the spread's whole point"
	)
	screen.free()


## The refusal is RENDERED rather than the control greyed out, and it is named. A
## player told nothing may still be told why nothing happened, and a panel that
## reworded the module's own constant would be describing a rule nobody wrote.
func test_a_shop_that_buys_nothing_refuses_the_sell_by_its_own_name() -> void:
	_shop = _hero(&"black_market", 0)
	var listed := ShopCatalog.instance().at_location(SHOP_LOCATION)
	assert_ne(listed.is_empty(), true, "setup: a stall trades at the reagent row")
	var black := _black_market_def()
	ShopCatalog.instance().install([black])
	var def := ShopCatalog.instance().definition(black.shop_id)
	assert_eq(def.buys_def(&"alchemy_mist_herb"), false, "setup: it buys nothing at all")
	var screen := _market(_shop)
	assert_eq(
		screen.select_shop(String(black.shop_id)),
		true,
		"an authored stall is selectable even when it buys nothing"
	)
	var sold := screen.act_sell("alchemy_mist_herb", 1)
	assert_eq(bool(sold["ok"]), false, "nothing to sell into, so there is nothing to hand over")
	assert_eq(
		bool(screen.summary()["enabled"]["sell"]),
		true,
		"and the control stays LIVE: the refusal is the module's, not the screen's guess"
	)
	screen.free()


## The refusal a player gets when the page has no seam is a NAMED one, and it is
## distinct from every module refusal: the shelf was priced and there is nowhere to
## send the trade. An unbound screen that quietly did nothing is the failure this
## whole assertion family exists for.
func test_an_unbound_market_screen_refuses_no_market_seam_by_name() -> void:
	_shop = _hero(&"unbound", 4000)
	var screen := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	screen.setup(_shop)
	screen.at_location(SHOP_LOCATION)
	screen.bind_market(Callable(), Callable(), Callable())
	assert_eq(bool(screen.summary()["market_wired"]), false, "the screen knows it cannot trade")
	screen.select_shop(String(SHOP_ID))
	var bought := screen.act_buy()
	assert_eq(bool(bought["ok"]), false, "so a buy cannot run")
	assert_eq(
		String(bought["reason"]),
		MarketScreen.NO_MARKET_SEAM,
		"and the refusal names the missing seam rather than reporting a purchase nobody ran"
	)
	assert_eq(
		ItemsApi.inventory(_shop).snapshot().stacks().is_empty(),
		false,
		"and the hero's bag holds only what they came in with: nothing was conjured"
	)
	screen.free()


## No location means no stalls, which is a different sentence from "the room is
## empty". The refusal is by name so one renderer covers both.
func test_a_market_with_no_location_names_no_shops_rather_than_listing_everyone() -> void:
	_shop = _hero(&"nowhere", 4000)
	var screen := (MARKET_SCENE as PackedScene).instantiate() as MarketScreen
	screen.setup(_shop)
	screen.bind_market(Callable(ShopCounter, "at_location"), Callable(), Callable())
	screen.bind_market(
		Callable(ShopCounter, "at_location"),
		func(_a: StringName, _p: Actor, _r: Array) -> Dictionary: return {},
		func(_a: StringName, _p: Actor, _r: Array) -> Dictionary: return {}
	)
	# Explicitly typed, not `:=`: `Dictionary` subscript is a `Variant`, and inferring
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
	var bought := screen.act_buy()
	assert_eq(String(bought["reason"]), MarketScreen.NO_LOCATION, "and the refusal says so")
	screen.free()


## Every authored stall is a row. A stall that silently vanished would read as content
## the build does not have, which is the dead-content failure ADR 0063 shipped once.
func test_every_authored_stall_at_a_row_is_listed_rather_than_truncated() -> void:
	_shop = _hero(&"browser", 4000)
	# Read the locations off the CONTENT tree rather than typing one in, so a retune of
	# a `.tres` cannot leave this suite probing a row the build no longer ships.
	var locations: Array[StringName] = []
	for id in ShopCatalog.instance().shop_ids():
		var def := ShopCatalog.instance().definition(id)
		if def != null and def.location_id != &"":
			locations.append(def.location_id)
	assert_ne(locations.is_empty(), true, "the catalog authors stalls that trade somewhere")
	for location in locations:
		var screen := _market(_shop)
		screen.at_location(location)
		var authored := ShopCounter.at_location(location, _shop).get("shops", []) as Array
		var listed := screen.summary()["shop_ids"] as Array
		assert_eq(
			listed.size(),
			authored.size(),
			"every stall at '%s' is a row, not the pool's size" % location
		)
		for row in authored:
			assert_eq(
				listed.has(String((row as Dictionary).get("shop_id", ""))),
				true,
				"%s has a row at '%s'" % [(row as Dictionary).get("shop_id", ""), location]
			)
		screen.free()


## The purse the screen publishes is the module's own, read through `MarketApi.summary`
## by bare name — the one facade call `ui/` may make here without a seam. Asserted
## against the module directly so a screen that re-derived a purse would go red.
##
## ## The message is formatted, never spliced
##
## A `Variant` reaches this as whatever it is, so `"%s" % reported` is the only way to
## name a whole dictionary here: the earlier `"...: %s" % offenders` form binds ONE
## array element to the single `%s` and Godot refuses the rest of the format string,
## which is a runtime error rather than a red assertion.
func test_the_screen_reports_the_purse_the_module_reads() -> void:
	_shop = _hero(&"counting", 777)
	var screen := _market(_shop)
	var reported := screen.summary()
	assert_eq(
		int(reported["purse"]),
		EconomyApi.purse(_shop),
		"the published purse is the module's, not one the screen composed"
	)
	var offenders := _non_primitives(reported, "")
	var offenders_text := str(offenders)
	assert_eq(
		offenders.is_empty(),
		true,
		"the published purse came with primitives only: %s" % offenders_text
	)
	screen.free()


# --- the auction, end to end -------------------------------------------------


## THE claim of the auction half. A player lists a lot, and the ESCROW is real — the
## good leaves their bag — and the lot shows up on the page with the frozen price and
## the required bid.
func test_a_player_lists_a_lot_and_it_appears_with_its_frozen_price_and_opening() -> void:
	var seller := _hero(&"lot_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"listed_spirit_stone")
	assert_ne(instance_id, "", "setup: the seller holds a realized instance to escrow")
	var screen := _auction(seller)
	assert_eq(
		screen.listable_instance_ids().has(instance_id),
		true,
		"the hero's own instance is listable, so the action is live"
	)
	assert_eq(
		ItemsApi.inventory(seller).count(AUCTION_GOOD),
		1,
		"and the good is in the bag before the escrow"
	)

	var listed := screen.act_list(instance_id, 3)
	assert_eq(bool(listed["ok"]), true, "the lot opens: %s" % listed["reason"])
	var lot_id := String(listed["lot_id"])
	assert_ne(lot_id, "", "and it has an id a row can be named by")
	assert_eq(
		ItemsApi.inventory(seller).instances().is_empty(),
		true,
		"the instance is ESCROWED out of the seller's bag, not copied (ADR 0102)"
	)

	var row := _lot_row_for(screen, lot_id)
	assert_ne(row, {}, "the lot is a row on the page")
	assert_eq(String(row["status"]), AuctionScreen.STATUS_OPEN, "and it is open")
	assert_eq(
		int(row["required_bid"]),
		int(listed["opening"]),
		"the row publishes the opening the module froze, so a bidder reads the real number"
	)
	assert_eq(bool(row["mine"]), true, "and the row knows the hero is its seller")
	assert_eq(
		bool(row["can_bid"]),
		false,
		"so the bid control is DEAD on your own lot, rather than live and refusing"
	)
	screen.free()


## THE claim of the second beat: a player lists nothing and bids on somebody's, and
## **the high bid is shown afterwards**. Asserted against the LEDGER and the row, so
## a screen that rendered a stale row cannot pass.
func test_a_player_bids_and_the_high_bid_is_shown_on_the_lot() -> void:
	var seller := _hero(&"rival_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"contested_stone")
	var listed := MarketApi.list(seller, StringName(instance_id), 3)
	assert_eq(bool(listed["ok"]), true, "setup: the rival listed a lot")
	var lot_id := String(listed["lot_id"])

	var bidder := _hero(&"hero", BIDDER_PURSE)
	var screen := _auction(bidder)
	var before := _lot_row_for(screen, lot_id)
	assert_ne(before, {}, "the rival's lot is on the page")
	assert_eq(String(before["high_bid"]), "", "nobody is bidding on it yet, and the row says so")
	assert_eq(bool(before["can_bid"]), true, "and this purse reaches the opening")

	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), true, "the bid is placed: %s" % bid["reason"])
	# ## The amount is `maxi(required, ceiling)`, and this purse's ceiling is ABOVE the
	# required bid
	#
	# `AuctionBids.bid` is the one place the bid figure exists: it derives
	# `AuctionState.bid_ceiling(purse, tags)` and takes `maxi(required, ceiling)`, so a
	# bidder with appetite to spare commits MORE than the minimum. A deep purse
	# therefore does NOT bid the required amount, and asserting it did was asserting the
	# auction's arithmetic wrong rather than the surface. What is asserted is the
	# ARITHMETIC, from both ends: the seam published the ceiling and the required bid,
	# and the ledger's standing is the maximum of the two.
	assert_eq(
		int(bid["amount"]),
		maxi(int(before["required_bid"]), int(bid["ceiling"])),
		"the standing is the auction's own maxi(required, ceiling)"
	)
	assert_eq(
		int(bid["required"]),
		int(before["required_bid"]),
		"and the required bid is the row's own figure"
	)
	assert_eq(
		int(bid["amount"]) >= int(before["required_bid"]),
		true,
		"a first bid on an unbid lot is never below the required amount"
	)
	# Read the lot back out of the LEDGER, not out of the return value: the return is
	# the seam's answer about itself, and the ledger is what the world now holds.
	var after := _lot_row_for(screen, lot_id)
	assert_eq(
		String(after["high_bid"]), String(bidder.id), "the ledger names this hero the high bidder"
	)
	assert_eq(int(after["high_bid_amount"]), int(bid["amount"]), "at the amount it committed")
	assert_eq(int(after["bid_count"]), 1, "and the lot records exactly one bid")
	# The row's OWN sentence, because "the high bid is shown" is a rendering claim and
	# a number-only assertion cannot see it.
	assert_ne(
		String(after["high_line"]).find(String(bidder.id)),
		-1,
		"the row PRINTS the high bidder's name, so a player can read who is winning"
	)
	assert_ne(
		String(after["high_line"]).find(str(int(bid["amount"]))), -1, "and the amount they stand at"
	)
	screen.free()


## A lot a hero cannot afford is a row that says so and a bid that is DEAD, which is
## the "looks alive and is dead" shape the UI standard exists to prevent. Asserted
## from the control state AND the refusal.
func test_a_lot_beyond_the_purse_is_not_bid_on_and_the_refusal_names_the_rule() -> void:
	var seller := _hero(&"rich_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"dear_stone")
	var listed := MarketApi.list(seller, StringName(instance_id), 3)
	assert_eq(bool(listed["ok"]), true, "setup: the lot is on the board")
	var lot_id := String(listed["lot_id"])
	var required := int(listed["opening"])

	var pauper := _hero(&"pauper", 1)
	var screen := _auction(pauper)
	var row := _lot_row_for(screen, lot_id)
	assert_ne(row, {}, "the lot is still visible to a hero who cannot afford it")
	assert_eq(bool(row["can_bid"]), false, "but the row reports it as beyond the purse")
	screen.select_lot(lot_id)
	assert_eq(
		bool(screen.summary()["enabled"]["bid"]),
		false,
		"so the bid control is DEAD, rather than live and refusing"
	)
	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), false, "and pressing anyway cannot place a bid")
	assert_eq(
		String(bid["reason"]),
		AuctionBids.CEILING_BELOW_REQUIRED,
		"the refusal is the AUCTION'S own id, passed through by name"
	)
	assert_eq(
		String(_lot()["high_bid"]), "", "and no bidder was recorded: a refusal writes nothing"
	)
	assert_eq(int(_lot()["high_bid_amount"]), 0, "at no amount either")
	screen.free()


## The seller cannot bid on their own lot, and the row says so before the press. The
## module's refusal is passed through rather than pre-judged, because
## `already_high` and `seller_is_bidder` are different sentences a panel reads.
func test_a_seller_cannot_bid_on_their_own_lot_and_the_refusal_names_the_rule() -> void:
	var seller := _hero(&"self_bidder", 9000)
	var instance_id := _instance(seller, AUCTION_GOOD, &"own_stone")
	var listed := screen_free_list(seller, instance_id)
	assert_eq(bool(listed["ok"]), true, "setup: the hero listed it")
	var lot_id := String(listed["lot_id"])

	var screen := _auction(seller)
	var bid := screen.act_bid(lot_id)
	assert_eq(bool(bid["ok"]), false, "a seller is not a bidder")
	assert_eq(
		String(bid["reason"]), MarketApi.SELLER_IS_BIDDER, "and the refusal is the module's id"
	)
	screen.free()


## A bid with no seam is refused BY NAME, distinct from every module refusal: the
## amount was computed and there was nowhere to send it. This is the assertion that
## keeps the `ROUTE_AUCTION` arm from being deleted silently.
func test_an_unbound_auction_screen_refuses_no_auction_seam_by_name() -> void:
	var seller := _hero(&"unbound_seller", 0)
	var instance_id := _instance(seller, AUCTION_GOOD, &"unbound_stone")
	var listed := screen_free_list(seller, instance_id)
	assert_eq(bool(listed["ok"]), true, "setup: a lot exists to bid on")

	var bidder := _hero(&"unbound_bidder", BIDDER_PURSE)
	var screen := (AUCTION_SCENE as PackedScene).instantiate() as AuctionScreen
	screen.setup(bidder)
	screen.bind_auction(Callable())
	assert_eq(bool(screen.summary()["auction_wired"]), false, "the screen knows it cannot bid")
	var bid := screen.act_bid(String(listed["lot_id"]))
	assert_eq(bool(bid["ok"]), false, "so a bid cannot run")
	assert_eq(
		String(bid["reason"]),
		AuctionScreen.NO_AUCTION_SEAM,
		"and the refusal names the missing seam rather than reporting a bid nobody placed"
	)
	assert_eq(String(_lot()["high_bid"]), "", "and no bidder was recorded")
	screen.free()


## Every lot in the world is a row, and a lot that silently vanished would read as
## content the build does not have. Stated against the facade's own count rather than
## a literal, so a content wave cannot leave this suite pinned to a number.
func test_every_lot_in_the_world_is_a_row_rather_than_truncated() -> void:
	var seller := _hero(&"lister", 0)
	for index in range(3):
		var instance_id := _instance(seller, AUCTION_GOOD, StringName("stone_%d" % index))
		assert_eq(
			bool(MarketApi.list(seller, StringName(instance_id), 3)["ok"]),
			true,
			"setup: lot %d is on the board" % index
		)
	var bidder := _hero(&"watcher", BIDDER_PURSE)
	var screen := _auction(bidder)
	assert_eq(
		(screen.summary()["lot_ids"] as Array).size(),
		_lots().size(),
		"one row per lot in the world, not the pool's size"
	)
	for row in _lots():
		assert_eq(
			(screen.summary()["lot_ids"] as Array).has(String((row as Dictionary)["lot_id"])),
			true,
			"%s has a row" % (row as Dictionary)["lot_id"]
		)
	screen.free()


## A good with no authored worth cannot be escrowed, and the refusal is the module's
## own id rather than a screen sentence. ADR 0094's floor makes an unauthored good
## CHEAP; an auction is not where a designer invents a first price.
func test_a_good_with_no_authored_worth_cannot_be_listed_and_says_so() -> void:
	var hero := _hero(&"listing_a_pebble", 0)
	var instance_id := _instance(hero, &"scroll_hemp", &"pebble")
	assert_ne(instance_id, "", "setup: the hero holds an unauthored good as an instance")
	var screen := _auction(hero)
	var listed := screen.act_list(instance_id, 3)
	assert_eq(bool(listed["ok"]), false, "an unpriced good refuses to list")
	assert_eq(
		String(listed["reason"]), MarketApi.LOT_UNPRICED, "and the refusal names the module's rule"
	)
	assert_eq(
		ItemsApi.inventory(hero).instances().size(),
		1,
		"and the good is untouched: a refused list escrows nothing"
	)
	screen.free()
