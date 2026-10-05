extends TestCase

## ADR 0250: a price that answers to who is buying. One bounded, injected,
## buyer-dependent factor — applied ONCE to the COIN COUNT — and the four things that
## make it safe: a hostile reader clamps, no reader changes nothing at all, the
## anti-arbitrage invariant holds in both directions, and a refused trade moves nothing.

const COIN := &"curr_spirit_coin"
## Carries an authored `trade_value` of 6 on a magic rarity at a spirit realm, so it
## prices at 13 rather than flooring to 1. **Every case that matters must trade this
## rather than an unauthored good**: at price 1 the `maxi(1, …)` floor collapses both
## legs and a whole class of directional bug is arithmetically invisible.
const VALUED := &"currency_spirit_stone"

## Every actor built here is held, because `Actor` is a `RefCounted` and one returned
## from a helper is freed the moment that helper returns — the ledger stores ids, never
## references. The auction suite holds for the same reason.
var _held: Array[Actor] = []


func setup() -> void:
	MarketApi.set_store(MarketWorldLedger.new())
	MarketFavour.set_reputation_reader(Callable())
	_held.clear()


## The reader is PROCESS-WIDE and the runner shares one process across every suite, so a
## reader left installed would silently re-price the market for everything that runs
## after this file — which is precisely the failure this suite exists to prevent.
func teardown() -> void:
	MarketFavour.set_reputation_reader(Callable())
	MarketApi.set_store(null)
	_held.clear()


# --- the default: no reader, byte-identical prices -------------------------------


## ## THE claim: with no reader bound the price is EXACTLY today's
##
## Taken before and after the seam is *released*, through the production reader rather
## than through `MarketFavour.factor` — a reader that clamps but is not wired into
## `MarketTransfer.quote` would pass every other case in this file, because the coin
## figures are produced by `quote` and nowhere else.
##
## `VALUED` rather than an unauthored good, for the reason every market case states: at
## price 1 the `maxi(1, …)` floor collapses both legs and a directional bug is invisible.
func test_no_reader_leaves_todays_price_byte_identical() -> void:
	var shop := _actor_with(VALUED, 10)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 1000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	MarketFavour.set_reputation_reader(Callable())
	assert_eq(MarketFavour.has_reputation_reader(), false, "setup: no reader is installed")

	var before_buy := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), true)
	# The SELL direction plans the offer leg against the PLAYER, so the buyer has to be
	# holding the goods or the quote is a refusal carrying no `coins` key at all.
	ItemsApi.inventory(buyer).add(Crafting.resolve(VALUED), 3)
	var before_sell := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), false)
	# A reader that answers the STRONGEST possible standing and the strongest possible
	# dislike, so a bound reader is proved to be able to move both legs below.
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	assert_eq(MarketFavour.has_reputation_reader(), true, "setup: and one can be installed")
	MarketFavour.set_reputation_reader(Callable())

	var after_buy := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), true)
	var after_sell := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), false)
	assert_eq(
		int(after_buy["coins"]),
		int(before_buy["coins"]),
		(
			"the BUY coins are unchanged: %d then %d"
			% [int(before_buy["coins"]), int(after_buy["coins"])]
		)
	)
	assert_eq(
		int(after_sell["coins"]),
		int(before_sell["coins"]),
		(
			"and so are the SELL coins: %d then %d"
			% [int(before_sell["coins"]), int(after_sell["coins"])]
		)
	)
	assert_eq(after_buy["offer"], before_buy["offer"], "and the offer leg, byte for byte")
	assert_eq(after_sell["want"], before_sell["want"], "and the want leg")


## The same claim through the verb rather than through `price`, so the assertion covers
## the shipped settlement and not only the helper. A one-coin-equality is exact because
## both sides are integers off the same formula.
func test_a_deal_settles_for_exactly_todays_coins_with_no_reader() -> void:
	var shop := _actor_with(VALUED, 10)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 1000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var neutral := MarketTransfer.price(shop, buyer, _rows(VALUED, 2), true)
	var purse := EconomyApi.purse(buyer)
	var bought := MarketApi.buy(shop, buyer, _rows(VALUED, 2))
	assert_eq(
		bool(bought["ok"]), true, "setup: the purchase settles: %s" % bought.get("reason", "")
	)
	assert_eq(
		int(bought["coins"]),
		int(neutral["coins"]),
		"the verb charged the neutral figure the helper quoted, with no reader installed"
	)
	assert_eq(purse - int(bought["coins"]), EconomyApi.purse(buyer), "and the purse agrees")


# --- the clamp: a hostile reader cannot move the economy -------------------------


## ## THE claim: a HOSTILE value clamps
##
## A `Callable` is arbitrary code, so the question is not "is the rate sensible" but
## "what can the worst plausible reader do". Every value below is one an injected seam
## could genuinely be handed: a stat mis-scaled by two orders of magnitude, an overflow,
## a NaN from a division by zero in whatever computes reputation, and the worst shape of
## all — a reader that returns nothing at all.
##
## The cap is asserted as a BOUND on the coin figure rather than on `factor` alone,
## because `factor` is an internal number and the coins are the economy.
func test_a_hostile_reader_cannot_push_a_price_past_the_clamp() -> void:
	for hostile in [100.0, 1000.0, 1.0e9, INF, -INF, -1000.0, NAN, 1.0e300]:
		MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return hostile)
		var shop := _actor_with(VALUED, 10)
		ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
		EconomyApi.attach(shop)
		var buyer := _actor_with(COIN, 100000)
		EconomyApi.attach(buyer)
		MarketApi.attach(buyer)
		var neutral := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), true)
		var claimed := MarketTransfer.price(shop, buyer, _rows(VALUED, 3), true)
		assert_eq(
			float(claimed["coins"]) <= float(neutral["coins"]) * MarketFavour.FAVOUR_CAP + 1.0,
			true,
			(
				"a reader answering %s charged %d against a neutral %d — at or under the cap"
				% [str(hostile), int(claimed["coins"]), int(neutral["coins"])]
			)
		)
		assert_eq(
			float(claimed["coins"]) >= float(neutral["coins"]) * MarketFavour.FAVOUR_FLOOR - 1.0,
			true,
			(
				"and at or over the floor: %d against a neutral %d"
				% [int(claimed["coins"]), int(neutral["coins"])]
			)
		)
		assert_eq(int(claimed["coins"]) >= 1, true, "and never a free good: still pays")


## A reader that answers the WRONG TYPE is neutral rather than an error, because a
## reader is a seam and a seam is allowed to be wrong. `true` is the case that matters:
## `float(true) == 1.0` in GDScript, so an unguarded cast would read a flag as a fully
## regarded buyer and hand the player a 15% discount for answering a boolean.
func test_a_reader_answering_the_wrong_shape_is_neutral() -> void:
	var shop := _actor_with(VALUED, 4)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var neutral := MarketTransfer.price(shop, buyer, _rows(VALUED, 2), true)
	for wrong in [true, false, "very popular", {}, [1, 2], null]:
		MarketFavour.set_reputation_reader(func(_buyer: Actor) -> Variant: return wrong)
		assert_eq(
			int(MarketTransfer.price(shop, buyer, _rows(VALUED, 2), true)["coins"]),
			int(neutral["coins"]),
			"a reader answering %s leaves the price exactly neutral" % str(wrong)
		)


## A DEAD reader is the same as none, so a caller that frees the object it bound reads
## today's price rather than raising at the first purchase. This is the seam outliving
## its subject — `is_valid()` is false for a callable naming a freed object.
##
## **A `Node` rather than a `RefCounted`, and `free()` rather than dropping the
## reference**: a `RefCounted` freed by refcount leaves its wrapper valid, so the seam
## still read as installed — and `doomed.free()` on one is an error, "Can't free a
## RefCounted object". That error aborted this test on its first run and reported no
## failure of its own, which is the abort shape `tools test.py`'s SCRIPT ERROR scan
## exists to catch. The node was never parented, so there is nothing to detach first.
func test_a_dead_reader_is_neutral_rather_than_a_crash() -> void:
	var shop := _actor_with(VALUED, 4)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var neutral := MarketTransfer.price(shop, buyer, _rows(VALUED, 2), true)
	var doomed := Node.new()
	# `get_class` rather than a name that does not exist: `Callable.is_valid()` is true for
	# a method every `Object` carries, so the ONLY thing this assertion can be measuring is
	# the node's life. A callable naming a missing method is dead from the moment it is
	# made, which would make `has_reputation_reader()` false before anything was freed.
	MarketFavour.set_reputation_reader(Callable(doomed, "get_class"))
	assert_eq(MarketFavour.has_reputation_reader(), true, "setup: it is live while it exists")
	doomed.free()
	assert_eq(
		MarketFavour.has_reputation_reader(),
		false,
		"and the seam reports itself dead rather than keeping the wrapper"
	)
	MarketFavour.set_reputation_reader(Callable())
	assert_eq(
		int(MarketTransfer.price(shop, buyer, _rows(VALUED, 2), true)["coins"]),
		int(neutral["coins"]),
		"so the price is today's price"
	)


## ## The panel and the verb must not part company (DEF-0219's whole subject)
##
## `ShopCounter.priced_rows` passes `null` for both actors, so the AUTHORED shelf is
## priced with no counter — which means `MarketFavour.factor(null)`, which is `1.0`. So
## the consequence is stated rather than left to be discovered: the authored PREVIEW is
## neutral by construction, and the modifier is a settlement-time haggling number.
##
## **This is a named limitation of ADR 0250, not an accident**, and it is asserted here
## so the day somebody wires the preview through, this case goes red and says what it
## costs. The alternative — threading the counter into the preview — would make a stall
## display a different number than it charges, which is worse than displaying the honest
## shelf rate.
func test_the_authored_shelf_preview_stays_neutral_and_the_goods_leg_is_never_revalued() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	# What a panel reads: authored stock priced with no actors at all.
	var preview := ShopCounter.priced_rows(
		ShopCatalog.instance().definition(&"foundation_reagent_trader"), true
	)
	assert_ne(preview.size(), 0, "setup: the authored shelf prices something")
	var priced_rows := 0
	for line in preview:
		# `unit_price` is `EconomyValuation`'s own number whatever the reader says: the
		# goods leg is never re-valued, in the preview or in the settlement.
		if int((line as Dictionary)["unit_price"]) > 0:
			priced_rows += 1
	assert_eq(
		priced_rows,
		preview.size(),
		"every preview row carries ADR 0094's own unit price, never a haggled one"
	)
	# And the settlement quote publishes a figure a caller can read BEFORE committing, so
	# a caller is never charged a number it had no way to see.
	var shop := _actor_with(VALUED, 4)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var quoted := MarketTransfer.quote(shop, buyer, _rows(VALUED, 2), true, buyer.id)
	assert_eq(bool(quoted["ok"]), true, "setup: the quote answers")
	assert_eq(int(quoted["coins"]) > 0, true, "and it is a real coin figure, not a hole")
	MarketFavour.set_reputation_reader(Callable())
	var neutral_quoted := MarketTransfer.quote(shop, buyer, _rows(VALUED, 2), true, buyer.id)
	assert_eq(
		int(quoted["coins"]) < int(neutral_quoted["coins"]),
		true,
		"a counter's regard discounts the charge the quote reports, and the quote is that number"
	)


# --- the modifier is real, bounded, and runs in BOTH directions -----------------


## ## The axis is not decorative — and the two directions INVERT
##
## Buying, a well-regarded counter charges LESS; selling, that same counter pays MORE.
## Both from ONE number, and the inversion is the yin-yang counterpart: a liked customer
## who could do both would gain twice, so the pair is what stops reputation from being a
## strict best response.
##
## Every side of the pair is asserted, because a modifier that moved only one direction
## would be an untaxable edge and this is the case that says so. `VALUED` throughout: at
## price 1 the `maxi(1, …)` floor collapses both legs and a directional bug is invisible.
func test_a_regarded_counter_charges_less_and_pays_more_and_the_reverse_is_also_true() -> void:
	var shop := _actor_with(VALUED, 10)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 100000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)

	# NEUTRAL first, on both sides, because everything else is a comparison against it.
	MarketFavour.set_reputation_reader(Callable())
	var neutral_charge := _charged(shop, buyer)
	var neutral_payout := _paid(shop, buyer)

	MarketFavour.set_reputation_reader(func(_counter: Actor) -> float: return 1.0)
	var liked_charge := _charged(shop, buyer)
	var liked_payout := _paid(shop, buyer)
	assert_eq(
		liked_charge < neutral_charge,
		true,
		"a liked buyer is CHARGED %d, under the neutral %d" % [liked_charge, neutral_charge]
	)
	assert_eq(
		liked_payout > neutral_payout,
		true,
		(
			"and PAID %d, over the neutral %d — the same axis, the other sign"
			% [liked_payout, neutral_payout]
		)
	)

	MarketFavour.set_reputation_reader(func(_counter: Actor) -> float: return -1.0)
	var disliked_charge := _charged(shop, buyer)
	var disliked_payout := _paid(shop, buyer)
	assert_eq(
		disliked_charge > neutral_charge,
		true,
		"a disliked buyer is CHARGED %d, over the neutral %d" % [disliked_charge, neutral_charge]
	)
	assert_eq(
		disliked_payout < neutral_payout,
		true,
		"and PAID %d, under the neutral %d" % [disliked_payout, neutral_payout]
	)
	# And the symmetry is EXACT, which is what "one number, two signs" means: the pair
	# is the same magnitude moved twice, so favour cannot compound in a direction.
	var discount := neutral_charge - liked_charge
	var surcharge := disliked_charge - neutral_charge
	assert_eq(
		discount > 0 and surcharge == discount,
		true,
		(
			(
				"the discount (%d) and the surcharge (%d) are the same size, so neither side "
				+ "is the better deal"
			)
			% [discount, surcharge]
		)
	)


## A discounted charge is never FREE and a surcharge never stops the trade: the clamp
## keeps the whole lever inside the spread's own 0.5..1.5 band, so a counter is still a
## counter to somebody it despises. The floor of 1 coin is `MarketSpread`'s own, carried
## through unchanged.
func test_the_clamp_keeps_the_leaver_inside_the_shops_own_margin() -> void:
	var shop := _actor_with(VALUED, 10)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 100000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	for reader in [-1.0, 1.0, 100.0, INF]:
		MarketFavour.set_reputation_reader(func(_counter: Actor) -> float: return reader)
		var charge := _charged(shop, buyer)
		var payout := _paid(shop, buyer)
		assert_eq(
			charge >= 1,
			true,
			"a reader at %s still charges %d — never free" % [str(reader), charge]
		)
		assert_eq(
			payout >= 1,
			true,
			"and still pays %d at %s — never nothing for a good" % [payout, str(reader)]
		)
		assert_eq(
			charge > payout,
			true,
			"and the counter still buys UNDER what it sells at %s" % str(reader)
		)


## ## The floor is not the spread and the cap is not ten times
##
## Two separate claims, kept separate: the lever is *bounded*, and the bound is *tighter
## than the shop's own margin* so fame is a discount and never a route to beating what a
## stranger pays. Both are stated against `MarketSpread`'s own published numbers.
func test_the_clamp_is_asymmetric_about_neutral_only_in_the_direction_it_claims() -> void:
	assert_eq(
		MarketFavour.FAVOUR_CAP < MarketSpread.SELL_RATE,
		true,
		(
			(
				"the cap (%.2f) is TIGHTER than the shop's own %.2f sell rate, so a "
				+ "well-regarded buyer never beats the margin a stranger pays"
			)
			% [MarketFavour.FAVOUR_CAP, MarketSpread.SELL_RATE]
		)
	)
	assert_eq(
		MarketFavour.FAVOUR_FLOOR > MarketSpread.BUY_RATE,
		true,
		(
			(
				"and the floor (%.2f) is TIGHTER than the shop's own %.2f buy rate, so a "
				+ "disliked seller is still paid above the rate a stranger would get"
			)
			% [MarketFavour.FAVOUR_FLOOR, MarketSpread.BUY_RATE]
		)
	)


## The clamp constants and the rate are ONE source, published so a panel and this suite
## read the invariant from the module rather than restating three numbers — and the rate
## cannot exceed the clamp, which is what makes the two redundant-but-not-dead.
func test_the_view_publishes_the_clamp_a_panel_and_a_test_read_together() -> void:
	MarketFavour.set_reputation_reader(Callable())
	var view := MarketFavour.view()
	assert_eq(bool(view["reader_installed"]), false, "no reader, and it says so")
	assert_eq(float(view["favour_cap"]), MarketFavour.FAVOUR_CAP, "the cap is published")
	assert_eq(float(view["favour_floor"]), MarketFavour.FAVOUR_FLOOR, "and the floor")
	assert_eq(float(view["favour_rate"]), MarketFavour.FAVOUR_RATE, "and the rate")
	assert_eq(
		MarketFavour.FAVOUR_FLOOR < 1.0 and 1.0 < MarketFavour.FAVOUR_CAP,
		true,
		"a reputation can move a price in BOTH directions, or it is not a reputation"
	)
	assert_eq(
		MarketFavour.FAVOUR_RATE * 1.0 <= MarketFavour.FAVOUR_CAP - 1.0,
		true,
		"a fully-regarded buyer cannot exceed the clamp on its own"
	)
	# And the facade publishes the same read, so a screen needs no module interior.
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 0.5)
	var reader := _actor_with(COIN, 10)
	var published: Dictionary = MarketApi.summary(reader)["favour"]
	assert_eq(
		bool(published["reader_installed"]),
		true,
		"and `MarketApi.summary` publishes the seam for a panel that may not name the class"
	)


## A discount is proportional to the COINS, never to the goods: the unit price the
## settlement's own guard reads is untouched. This is the structural proof that no leg
## can invert — asserted through `EconomyValuation` directly rather than through the
## quote, so it is the formula itself being checked and not the module's copy of it.
func test_the_goods_leg_keeps_its_unmodified_valuation_under_any_reputation() -> void:
	var probe := ItemInstance.new(VALUED, &"favour_probe")
	var def := Crafting.resolve(VALUED)
	probe.def_ref = def
	probe.rarity = def.rarity
	probe.realm = def.realm
	var unmodified := EconomyValuation.price_of(probe)
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	assert_eq(
		EconomyValuation.price_of(probe),
		unmodified,
		"a bound reader does not move ADR 0094's price at all: the formula is untouched"
	)
	assert_eq(
		EconomyApi.valuation(VALUED)["price"],
		unmodified,
		"and neither does the facade's own read of it"
	)


# --- the anti-arbitrage invariant ------------------------------------------------


## ## THE invariant: the offerer never receives more value than it gives
##
## Asserted with the WORST reader rather than a friendly one, in BOTH directions, on a
## genuinely-priced good. A one-way modifier is invisible here at price 1 and at zero
## reputation, which is why the reader answers the maximum and the rows are `VALUED`.
func test_the_exchange_invariant_holds_under_the_worst_reader_in_both_directions() -> void:
	for hostile in [-1.0, 0.0, 1.0]:
		MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return hostile)
		var shop := _actor_with(VALUED, 20)
		ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
		EconomyApi.attach(shop)
		var buyer := _actor_with(COIN, 100000)
		EconomyApi.attach(buyer)
		MarketApi.attach(buyer)
		for quantity in [1, 2, 5]:
			# Shop sells: the player hands over COINS and receives GOODS.
			var buying := MarketApi.buy(shop, buyer, _rows(VALUED, quantity))
			assert_eq(
				bool(buying["ok"]),
				true,
				(
					"a reader at %s must not invert the buying leg for %d: %s"
					% [str(hostile), quantity, buying.get("reason", "")]
				)
			)
			assert_eq(
				int(buying["received"]) <= int(buying["offered"]),
				true,
				(
					"received %d <= offered %d on a purchase at %s"
					% [int(buying["received"]), int(buying["offered"]), str(hostile)]
				)
			)
			# Player sells: the player hands over GOODS and receives COINS.
			var selling := MarketApi.sell(null, shop, buyer, _rows(VALUED, quantity))
			assert_eq(
				bool(selling["ok"]),
				true,
				(
					"a reader at %s must not invert the selling leg for %d: %s"
					% [str(hostile), quantity, selling.get("reason", "")]
				)
			)
			assert_eq(
				int(selling["received"]) <= int(selling["offered"]),
				true,
				(
					"received %d <= offered %d on a sale at %s"
					% [int(selling["received"]), int(selling["offered"]), str(hostile)]
				)
			)


## A shop round trip still costs the player money with a reader bound at the extreme
## that HELPS them most — the direction a broken modifier would leak in. A favourite who
## buys at the floor and sells at the floor gains 0.85x on both legs, so the spread still
## eats them; this is the assertion that says the discount can never invert ADR 0100.
func test_the_most_favoured_round_trip_still_costs_the_player() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	var shop := _actor_with(VALUED, 20)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 100000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var bought := MarketApi.buy(shop, buyer, _rows(VALUED, 4))
	assert_eq(bool(bought["ok"]), true, "the purchase settles: %s" % bought.get("reason", ""))
	var sold := MarketApi.sell(null, shop, buyer, _rows(VALUED, 4))
	assert_eq(bool(sold["ok"]), true, "the resale settles: %s" % sold.get("reason", ""))
	assert_eq(
		int(sold["coins"]) < int(bought["coins"]),
		true,
		(
			"the most-favoured buyer still lost %d on a round trip"
			% (int(bought["coins"]) - int(sold["coins"]))
		)
	)


## Nothing mints the numeraire: the modifier moves coins BETWEEN two parties, so the
## total over the pair is conserved whatever the reader says. This is the "never free
## money" claim stated as a conservation law rather than as a comparison.
func test_the_modifier_moves_coins_without_minting_them() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	var shop := _actor_with(VALUED, 20)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 100000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var before := ItemsApi.inventory(buyer).count(COIN) + ItemsApi.inventory(shop).count(COIN)
	MarketApi.buy(shop, buyer, _rows(VALUED, 3))
	MarketApi.sell(null, shop, buyer, _rows(VALUED, 3))
	var after := ItemsApi.inventory(buyer).count(COIN) + ItemsApi.inventory(shop).count(COIN)
	assert_eq(before, after, "a favour-weighted buy-then-sell moves coins around and mints none")


# --- a refused trade moves nothing ------------------------------------------------


## ## THE refusal claim: a refused trade moves nothing, WITH a reader bound
##
## A bound reader is a new input to every price, and a new input to a price is exactly
## where a half-settled trade would hide. Three distinct refusals are checked against
## the bags, because they fail at different depths: the shop does not list the good (a
## content refusal before any pricing), the player cannot fund the charge, and the shop
## cannot fund the payout. Each is read off BOTH inventories.
func test_a_refused_trade_moves_nothing_with_a_reader_bound() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return -1.0)
	var black := ShopDef.new()
	black.shop_id = &"favour_black_market"
	black.buys = [&"scroll_rice"]
	var shop := _actor_with(VALUED, 4)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 0)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 500)
	ItemsApi.inventory(buyer).add(Crafting.resolve(VALUED), 2)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)

	# Refusal one: the shop does not BUY this good. The refusal happens before any
	# price is consulted, so it is the control for the other two.
	var shelf_before := _snapshot(shop)
	var purse_before := EconomyApi.purse(buyer)
	var unlisted := MarketApi.sell(black, shop, buyer, _rows(VALUED, 1))
	assert_eq(bool(unlisted["ok"]), false, "an unlisted good is not bought")
	assert_eq(String(unlisted["reason"]), MarketApi.SHOP_WILL_NOT_BUY, "and names the rule")
	assert_eq(_snapshot(shop), shelf_before, "nothing moved in the shop's bag")
	assert_eq(EconomyApi.purse(buyer), purse_before, "and not a coin either way")

	# Refusal two: the SHOP cannot fund the payout, and the reader is pushing the price
	# UP, so the priced figure is the largest it will ever be here.
	var unfunded := MarketApi.sell(null, shop, buyer, _rows(VALUED, 1))
	assert_eq(bool(unfunded["ok"]), false, "an unfunded shop refuses to buy")
	assert_eq(String(unfunded["reason"]), MarketTransfer.SHOP_CANNOT_PAY, "and says so")
	assert_eq(ItemsApi.inventory(buyer).count(VALUED), 2, "the buyer keeps every unit")

	# Refusal three: the PLAYER cannot fund the charge. The goods are on the shelf and
	# the price is real, so this is the refusal that would expose an inverted leg.
	var broke := _actor_with(COIN, 1)
	EconomyApi.attach(broke)
	MarketApi.attach(broke)
	var poor := MarketApi.buy(shop, broke, _rows(VALUED, 4))
	assert_eq(bool(poor["ok"]), false, "a player who cannot cover the charge is refused")
	assert_eq(ItemsApi.inventory(broke).count(VALUED), 0, "and is handed no goods")
	assert_eq(ItemsApi.inventory(shop).count(VALUED), 4, "and the shop keeps every unit")


## A refused trade moves nothing at the OTHER extreme too, so the claim is not an
## artefact of the one reader the case above happened to bind.
func test_a_refused_purchase_moves_nothing_at_the_other_extreme() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	var shop := _actor_with(VALUED, 1)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 1000)
	EconomyApi.attach(shop)
	var buyer := _actor_with(COIN, 0)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	var refused := MarketApi.buy(shop, buyer, _rows(VALUED, 1))
	assert_eq(bool(refused["ok"]), false, "a broke player is refused")
	assert_eq(ItemsApi.inventory(buyer).count(VALUED), 0, "and is given nothing")
	assert_eq(ItemsApi.inventory(shop).count(VALUED), 1, "and the shelf is intact")
	assert_eq(EconomyApi.purse(buyer), 0, "and the purse never went negative")


## The floor is untouched by a reader: it is not a price, and a discount that reached
## the escrowed good would let two parties split one item at a fraction of its worth.
func test_the_floor_and_the_auction_reserve_are_not_repriced_by_a_reader() -> void:
	MarketFavour.set_reputation_reader(func(_buyer: Actor) -> float: return 1.0)
	var dropper := _actor_with(VALUED, 2)
	EconomyApi.attach(dropper)
	MarketApi.attach(dropper)
	var dropped := MarketApi.drop(dropper, &"reagent_row", _rows(VALUED, 1))
	assert_eq(bool(dropped["ok"]), true, "setup: the good reaches the floor")

	var seller := _actor_with(COIN, 0)
	ItemsApi.inventory(seller).add(Crafting.resolve(VALUED), 2)
	EconomyApi.attach(seller)
	MarketApi.attach(seller)
	var def := Crafting.resolve(VALUED)
	var instance := ItemInstance.new(def.id, &"favour_lot")
	instance.def_ref = def
	instance.rarity = def.rarity
	instance.realm = def.realm
	instance.rolled = []
	ItemsApi.inventory(seller).add_instance(instance)
	var frozen := EconomyValuation.price_of(instance)
	var listed := MarketApi.list(seller, instance.instance_id, 3)
	assert_eq(bool(listed["ok"]), true, "setup: the lot opens: %s" % listed.get("reason", ""))
	assert_eq(
		int(listed["price"]),
		frozen,
		(
			"a lot's reserve is ADR 0094's price, frozen at escrow — a bidder's standing may "
			+ "not move it, or the reserve and the opening bid would disagree"
		)
	)


# --- fixtures ---------------------------------------------------------------------


func _actor_with(def_id: StringName, quantity: int) -> Actor:
	var actor := Actor.new()
	actor.id = &"favour_actor"
	ItemsApi.attach(actor)
	if quantity > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(def_id), quantity)
	_held.append(actor)
	return actor


func _rows(def_id: StringName, quantity: int) -> Array:
	return [{"def_id": String(def_id), "quantity": quantity}]


## What the player is CHARGED for `3` of the valued good at this counter — the shop
## selling. Through `price`, which refuses `SHOP_CANNOT_PAY` rather than returning a
## `coins` key when the PAYER cannot cover it, so both helpers hold a funded counter and
## a funded buyer. **A refusal returns no `coins` key at all**, so reading `["coins"]`
## straight off an unfunded fixture is a runtime error rather than a red assertion — which
## is what two cases here hit on their first run.
func _charged(shop: Actor, buyer: Actor) -> int:
	return int(MarketTransfer.price(shop, buyer, _rows(VALUED, 3), true)["coins"])


## ## What the player is PAID for the same row at the same counter — the shop buying, and
## ## the direction that INVERTS the sign.
##
## ## The PLAYER must hold the goods here, and that is the fixture, not a detail
##
## `MarketTransfer.price(shop, buyer, rows, false)` plans the `offer` leg against the
## PLAYER, so a buyer holding no `VALUED` reads `not_carried` — and a **refusal carries no
## `coins` key at all**, so the failure arrives as a runtime error rather than a red
## assertion. Buying plans against the SHOP instead, which is why `_charged` needs nothing
## put in the buyer's bag. Four cases hit this on their first run.
func _paid(shop: Actor, buyer: Actor) -> int:
	ItemsApi.inventory(buyer).add(Crafting.resolve(VALUED), 3)
	return int(MarketTransfer.price(shop, buyer, _rows(VALUED, 3), false)["coins"])


## Every stack in a bag, as primitives, so "nothing moved" is a real comparison of the
## whole bag rather than of one `count` that would miss a swap between two slots.
func _snapshot(actor: Actor) -> Array:
	var out: Array = []
	for stack in ItemsApi.inventory(actor).stacks():
		(
			out
			. append(
				[
					String(stack.def_id),
					int(stack.quantity),
					String(stack.signature()),
				]
			)
		)
	out.sort_custom(
		func(a: Array, b: Array) -> bool: return str(a[0]) + str(a[2]) < str(b[0]) + str(b[2])
	)
	return out
