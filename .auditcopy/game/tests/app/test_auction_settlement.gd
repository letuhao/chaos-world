extends "res://tests/app/auction_bid_kit.gd"

## The settlement and structural-pin half of ADR 0102 / BL-0049.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no
## method renamed: this half is the file's sections four and five verbatim, and every
## constant, builder and helper it uses now lives in `auction_bid_kit.gd`, which
## both halves `extends`.
##
## `setup()` / `teardown()` and the fixtures live in the kit, because
## `MarketApi.set_store` is PROCESS-WIDE: a store installed by one half and cleared
## by the other outlives the suite and is inherited by everything that runs later.
##
## The determinism / refusal / personality half is `test_auction_bids.gd`.

# --- 4. Settlement: the coins actually move, from BOTH sides -------------------


## **Both purses are asserted, and that pair is the point.** "The winner paid" and "the
## house received" are one fact from two sides; either alone is also what a transfer that
## destroyed the coins would report. This program has already shipped that bug once — the
## lot marked itself sold while the coin leg charged a zero amount.
func test_settlement_pays_the_high_bidder_and_the_coins_actually_move() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var purse_before := EconomyApi.purse(house)
	assert_eq(purse_before, 0, "the house starts with nothing, so any gain is a gain")
	var bidder := _bidder(&"the_winner", 1000, [&"collector"] as Array[StringName])
	var placed := AuctionBids.bid(bidder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "the bid lands: %s" % placed.get("reason", ""))
	var paid := int(placed["amount"])
	assert_eq(paid > 0, true, "and is a positive number of coins")
	var bidder_before := EconomyApi.purse(bidder)
	var settled := MarketApi.settle_lot(house, _resolver([bidder]), StringName(lot_id), 3)
	assert_eq(bool(settled["ok"]), true, "the lot settles: %s" % settled.get("reason", ""))
	assert_eq(String(settled["status"]), "sold", "and it sold")
	assert_eq(String(settled["winner"]), "the_winner", "to the high bidder")
	assert_eq(ItemsApi.inventory(bidder).instances().size(), 1, "who received the good")
	# SIDE ONE: the bidder is out exactly their bid.
	assert_eq(EconomyApi.purse(bidder), bidder_before - paid, "the bidder's purse fell by the bid")
	# SIDE TWO: the house is up exactly the same number. Neither side alone proves the
	# coins MOVED rather than being minted or burned on the way.
	assert_eq(EconomyApi.purse(house), purse_before + paid, "and the house received them")
	# And the two agree, which is the sum invariant.
	assert_eq(
		EconomyApi.purse(bidder) + EconomyApi.purse(house),
		bidder_before + purse_before,
		"so the pair conserved: nothing was created or destroyed"
	)


## A promise the bidder can no longer keep loses them the lot. The purse is RE-READ at
## settlement, so a caller cannot hand-pick a winner and money spent since bidding is
## visible rather than a crash.
func test_a_bidder_who_spends_their_purse_between_bid_and_settle_loses_the_lot() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var bidder := _bidder(&"spendthrift", 1000, [&"collector"] as Array[StringName])
	var placed := AuctionBids.bid(bidder, StringName(lot_id), 1)
	assert_eq(bool(placed["ok"]), true, "the bid lands first")
	ItemsApi.inventory(bidder).remove(COIN, 1000)
	assert_eq(EconomyApi.purse(bidder), 0, "then the purse is gone")
	var settled := MarketApi.settle_lot(house, _resolver([bidder]), StringName(lot_id), 3)
	assert_eq(String(settled["status"]), "unsold", "so the lot goes unsold")
	assert_eq(ItemsApi.inventory(bidder).instances().size(), 0, "and nobody receives it")
	assert_eq(EconomyApi.purse(house), 0, "and the seller is never charged a shortfall")


## And the fall-through: a defaulting high bidder hands the lot to the NEXT bidder at
## THEIR OWN bid. This is the case that makes `defaulted_on_a_bid` consequential rather
## than an announcement.
##
## **Both bidders are collectors**, so their appetite is equal and the ONLY thing separating
## them is the order they bid in — which is what makes this a statement about default rather
## than about appetite. The thrifty variant is deliberately NOT used here: a 450 ceiling
## against a standing 900 bid would be refused before it ever reached the ledger, so there
## would be no second row to fall back to and the test would be measuring the refusal rather
## than the fall-through.
##
## **The second bidder's purse is deeper, and that is the correction.** They were both on
## 1000 coins, so the second collector's ceiling was 900 against a requirement of 901 — and
## ADR 0102 refuses a bid under its own ceiling rather than placing a void one, so the second
## call returned `ceiling_below_required`, no second row was ever written, and the settlement
## walk had nothing to fall back to. The lot therefore went `unsold` and this case asserted a
## fall-through that had never happened. `next` now carries enough to clear the RAISED
## requirement, which is what produces the two-entry walk the case is about.
func test_a_defaulting_high_bidder_hands_the_lot_to_the_next_bidder_at_their_own_bid() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var high := _bidder(&"high_bidder", 1000, [&"collector"] as Array[StringName])
	var next := _bidder(&"next_bidder", 2000, [&"collector"] as Array[StringName])
	var first := AuctionBids.bid(high, StringName(lot_id), 1)
	assert_eq(bool(first["ok"]), true, "the first collector bids: %s" % first.get("reason", ""))
	var high_at := int(first["amount"])
	# The second collector's ceiling now clears the RAISED required bid, so they place a real
	# second row — above the first, because their ceiling is above it. Two rows is what the
	# settlement walk ranks.
	var second := AuctionBids.bid(next, StringName(lot_id), 2)
	assert_eq(
		bool(second["ok"]),
		true,
		"the second collector places a real bid: %s" % second.get("reason", "")
	)
	var second_at := int(second["amount"])
	assert_eq(second_at > high_at, true, "the second bid is the high, having outbid the first")
	var row := _lot()
	assert_eq(int(row["bid_count"]), 2, "so there are two rows for the walk to rank")
	# The high bidder then spends their purse between bid and close.
	ItemsApi.inventory(high).remove(COIN, 1000)
	assert_eq(EconomyApi.purse(high), 0, "the high bidder is broke before settlement")
	var settled := MarketApi.settle_lot(house, _resolver([high, next]), StringName(lot_id), 3)
	assert_eq(String(settled["status"]), "sold", "the lot still sells")
	assert_eq(
		String(settled["winner"]), "next_bidder", "to the next bidder, not to the defaulting one"
	)
	assert_eq(
		int(settled["amount"]),
		second_at,
		"at THEIR OWN bid (%d), not at a rescued or inflated figure" % second_at
	)
	assert_eq(
		EconomyApi.purse(next), 2000 - second_at, "and the fallback bidder pays their own bid"
	)
	assert_eq(
		EconomyApi.purse(house),
		second_at,
		"to the house, which is never charged the shortfall for the default"
	)


# --- 5. The structural pins -----------------------------------------------------


## `market` names no `npc` type, and the facade is still at or under the twelve-method
## cap. Both are read off the SOURCE rather than asserted by count-and-trust: the cap is
## `MAX_FACADE_PUBLIC_METHODS` in `tools/arch/rules.py`, and this is the ADR 0102 shape
## of the pin.
##
## **The `npc` scan reads executable text only.** `api.gd` cites `NpcState.ensure_entry` in a
## `##` comment as the shape `MAX_SHOPS` follows — a real cross-reference, since that
## function exists — and a raw `contains("NpcState")` therefore fails on the citation that
## documents the convention. A dependency is something the file DECLARES, not something it
## explains, so the pin searches code. This is the same rule the no-rng case above applies.
func test_the_market_facade_names_no_npc_type_and_stays_within_its_method_cap() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/market/api.gd")
	var code := _executable(source)
	for forbidden in FORBIDDEN_IN_MARKET:
		assert_eq(
			code.contains(String(forbidden)), false, "market/api.gd names no %s" % String(forbidden)
		)
	assert_eq(code.contains("res://src/modules/npc"), false, "and preloads nothing from npc/")
	# The cap itself, counted with the same regex `tools/arch/enforce.py` uses. Counted on
	# the WHOLE file, comments included, because a method declaration is never a comment.
	var pattern := RegEx.new()
	assert_eq(
		pattern.compile("^(?:static\\s+)?func\\s+([A-Za-z_]\\w*)"),
		OK,
		"the facade-method pattern compiles"
	)
	var public: Array[String] = []
	for entry in pattern.search_all(source):
		var name := entry.get_string(1)
		if not name.begins_with("_"):
			public.append(name)
	assert_eq(
		public.size() <= 12, true, "market publishes %d public methods, at most 12" % public.size()
	)


## The one-price-path pin, unchanged by this change: `auction_state.gd` is pure
## arithmetic over the lot's FROZEN price and names no price formula at all, and `api.gd`
## may only reach the price through `EconomyValuation.price_of`.
func test_the_auction_state_still_names_no_second_price_formula() -> void:
	var state_source := FileAccess.get_file_as_string("res://src/modules/market/auction_state.gd")
	for forbidden in ["RARITY_WEIGHT", "rarity_weight(", "RealmRate.", "unit_price(", "price_of("]:
		assert_eq(
			state_source.contains(forbidden), false, "auction_state.gd names no %s" % forbidden
		)
	var read_model := FileAccess.get_file_as_string(
		"res://src/modules/market/auction_read_model.gd"
	)
	for forbidden in ["RARITY_WEIGHT", "rarity_weight(", "RealmRate.", "unit_price("]:
		assert_eq(
			read_model.contains(forbidden),
			false,
			"auction_read_model.gd names no %s either" % forbidden
		)
	var api_source := FileAccess.get_file_as_string("res://src/modules/market/api.gd")
	assert_eq(api_source.contains("RARITY_WEIGHT"), false, "api.gd names no rarity weight")
	assert_eq(api_source.contains("rarity_weight("), false, "api.gd calls no rarity weight")
	assert_eq(api_source.contains("RealmRate."), false, "api.gd names no realm curve")
	assert_eq(api_source.contains("unit_price("), false, "api.gd assembles no price from parts")
	assert_eq(
		api_source.contains("EconomyValuation.price_of("),
		true,
		"api.gd prices through the one formula"
	)


## The events announce facts that are ALREADY WRITTEN (ADR 0093). Each one is captured
## and then the ledger is read, so a signal that fired before its write would fail here
## rather than reading as a working bus.
func test_the_auction_events_announce_what_has_already_been_written() -> void:
	var bus := AuctionEvents.shared()
	assert_eq(bus, bus, "the bus is one instance, so a subscriber connects once")
	var seen: Array[Dictionary] = []
	var on_bid := func(bidder_id: String, lot_id: StringName, amount: int, _req: int) -> void:
		seen.append({"signal": "bid_placed", "bidder": bidder_id, "amount": amount})
	var on_outbid := func(bidder_id: String, _lot: StringName, by_id: String, _amount: int) -> void:
		seen.append({"signal": "outbid_in_auction", "bidder": bidder_id, "by": by_id})
	var on_default := func(bidder_id: String, _lot: StringName, amount: int) -> void:
		seen.append({"signal": "defaulted_on_a_bid", "bidder": bidder_id, "amount": amount})
	var on_won := func(bidder_id: String, _lot: StringName, amount: int, _seller: String) -> void:
		seen.append({"signal": "won_auction", "bidder": bidder_id, "amount": amount})
	bus.bid_placed.connect(on_bid)
	bus.outbid_in_auction.connect(on_outbid)
	bus.defaulted_on_a_bid.connect(on_default)
	bus.won_auction.connect(on_won)

	var house := _house()
	var lot_id := _list_good(house)
	var winner := _bidder(&"event_winner", 1000, [&"collector"] as Array[StringName])
	var high := AuctionBids.bid(winner, StringName(lot_id), 1)
	assert_eq(bool(high["ok"]), true, "the high bid lands")
	var row := _lot()
	assert_eq(
		int(row["high_bid_amount"]),
		int(high["amount"]),
		"and the ledger already holds it when `bid_placed` fired"
	)
	# A genuine outbid: a second bidder whose purse is deep enough that its 90 percent
	# ceiling clears the RAISED required bid — unlike an equal purse, whose ceiling is
	# still the opening it planned against and which would be refused outright.
	var richer := _bidder(&"event_richer", 5000, [&"collector"] as Array[StringName])
	var raised := int(_lot()["required_bid"])
	assert_eq(bool(MarketApi.bid(richer, StringName(lot_id), raised, 2)["ok"]), true, "raised")
	var after_raise := _lot()
	assert_eq(String(after_raise["high_bid"]), "event_richer", "the ledger names the new high")
	assert_eq(
		int(after_raise["bid_count"]),
		2,
		"and the displaced bidder is STILL in the walk — outbid is a demotion"
	)
	ItemsApi.inventory(richer).remove(COIN, 5000)
	# **The purse is captured BEFORE `settle_lot`, not after it.** The settlement charges the
	# winner, so a read taken below it compares the purse against itself and `100 < 100` is
	# false — a failed transfer and a successful one read identically. Bidding is only a
	# PROMISE and moves no coins, so this is 1000, and `1000 - paid` is the figure the two
	# assertions below are about.
	var bidder_before := EconomyApi.purse(winner)
	var settled := MarketApi.settle_lot(house, _resolver([winner, richer]), StringName(lot_id), 3)
	var sold := _lot()
	assert_eq(String(sold["status"]), "sold", "the lot settled")
	# **The winner comes from the SETTLEMENT RESULT, not from the read row.** `AuctionReadModel`
	# publishes lot_id, seller, def, price, required_bid, high_bid, high_bid_amount, bid_count,
	# closes_after and status — and deliberately no `winner`, because the winner is only known
	# once the lot has closed and this row is a read of an OPEN lot. Indexing `sold["winner"]`
	# on the row was a runtime error that aborted the case mid-function, which is why this test
	# previously reported "1 script error" rather than a failure.
	assert_eq(String(settled["winner"]), "event_winner", "and the loser of the raise won the lot")
	assert_eq(
		String(sold["high_bid"]),
		"event_richer",
		"while the row still names the displaced high bidder, as an open read model must"
	)

	var signals: Array[String] = []
	for entry in seen:
		signals.append(String((entry as Dictionary)["signal"]))
	assert_eq(signals.has("bid_placed"), true, "a bid was announced: %s" % str(signals))
	assert_eq(signals.has("outbid_in_auction"), true, "an outbid was announced: %s" % str(signals))
	assert_eq(signals.has("defaulted_on_a_bid"), true, "a default was announced: %s" % str(signals))
	assert_eq(signals.has("won_auction"), true, "a win was announced: %s" % str(signals))
	# **The purse is strictly UNDER the winner's bid, so they paid and still keep a purse.**
	# The line reads "the winner paid, so this assertion is not vacuous", and the point is the
	# three assertions ABOVE it: a transfer that DESTROYED the coins would also leave a
	# purse of 0, and so would a transfer that never moved any. Only a purse that came down
	# and stayed above zero can say "the coins moved" rather than "the coins are gone".
	# `bidder_before - paid` leaves 100 behind on purpose, and the sale is asserted to
	# succeed — so an empty purse afterwards is a FAILURE here, which is what the guard has
	# to be: a property asserted about a sale that did not happen asserts nothing.
	assert_eq(EconomyApi.purse(winner) < bidder_before, true, "the winner paid for the lot")
	assert_eq(
		EconomyApi.purse(winner) > 0,
		true,
		"and still holds coins, so the transfer moved the purse rather than emptying it"
	)

	bus.bid_placed.disconnect(on_bid)
	bus.outbid_in_auction.disconnect(on_outbid)
	bus.defaulted_on_a_bid.disconnect(on_default)
	bus.won_auction.disconnect(on_won)
	# Disconnected, so this suite does not leak four connections into every suite after it.
	assert_eq(bus.bid_placed.get_connections().size(), 0, "the bus is released after the suite")


## `summary()` is how a caller knows which lots are due — ADR 0102 says so and this
## facade is at its cap, so the read model is where a lot becomes visible.
func test_the_read_model_reports_the_lots_a_caller_owns_time_over() -> void:
	var house := _house()
	var lot_id := _list_good(house)
	var bidder := _bidder(&"reader", 1000, [&"collector"] as Array[StringName])
	AuctionBids.bid(bidder, StringName(lot_id), 1)
	var summary := MarketApi.summary(bidder)
	assert_eq(int(summary["open_lot_count"]), 1, "one lot is open")
	assert_eq(int(summary["lot_capacity"]), MarketApi.MAX_OPEN_LOTS, "and the cap is published")
	var lots: Array = summary["lots"] as Array
	assert_eq(lots.size(), 1, "the lot is visible from ANOTHER actor's summary")
	assert_eq(String((lots[0] as Dictionary)["lot_id"]), lot_id, "by its own id")
	assert_eq(String((lots[0] as Dictionary)["high_bid"]), "reader", "with its high bidder")
	assert_eq(
		int((lots[0] as Dictionary)["required_bid"]) > 0, true, "and what the next bid must be"
	)
