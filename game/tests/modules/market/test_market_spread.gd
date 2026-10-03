extends TestCase

## ADR 0100: a margin lives in the coins, and a shop is an Actor. The assertions are about
## the SPREAD being un-exploitable, because a market maker that can print money is worse
## than no market maker.

const COIN := &"curr_spirit_coin"
const GOOD := &"currency_spirit_stone"
const CHEAP := &"scroll_hemp"

## `GOOD` carries an authored `trade_value` of 6 on a magic rarity at a spirit realm, so it
## prices at 13 rather than flooring to 1. **Every spread test that matters must trade this
## rather than `CHEAP`**: at price 1 the `maxi(1, …)` floor collapses both legs, and a whole
## class of directional bug is arithmetically invisible. `CHEAP` ships no worth at all, so it
## is only useful as a "this costs nothing meaningful" control.
const VALUED := &"currency_spirit_stone"


func setup() -> void:
	pass


func test_the_spread_is_a_constant_invariant() -> void:
	# The ADR 0084 shape: `tools arch` cannot compute a value it does not compute, so the
	# invariant that no round trip is profitable is asserted as a test, not left to a comment.
	assert_eq(MarketSpread.BUY_RATE < MarketSpread.SELL_RATE, true, "buy is below sell")
	assert_eq(
		MarketSpread.BUY_RATE <= 1.0 and 1.0 <= MarketSpread.SELL_RATE,
		true,
		"the one price sits between the two rates"
	)


func test_a_round_trip_always_costs_the_player() -> void:
	for unit in [1, 5, 13, 100, 412]:
		assert_eq(
			MarketSpread.round_trip_cost(unit) > 0,
			true,
			"buying and selling back at %d loses money" % unit
		)


func test_the_spread_view_reports_no_arbitrage() -> void:
	var view := MarketSpread.view()
	assert_eq(bool(view["arbitrage_possible"]), false, "the spread reports no arbitrage")
	assert_eq(int(view["round_trip_loss"]) > 0, true, "and a positive round-trip loss")


func test_buy_and_sell_prices_straddle_the_one_price() -> void:
	var unit := EconomyValuation.unit_price(10.0, ItemRarity.COMMON, &"")
	assert_eq(MarketSpread.buy_price(unit) < unit, true, "a shop pays under the price")
	assert_eq(MarketSpread.sell_price(unit) > unit, true, "and charges over it")


func test_a_shop_buys_a_genuinely_priced_good() -> void:
	# **This is the test whose absence let an inverted settlement ship.** Every other spread
	# test trades `scroll_hemp`, which ships no `trade_value`, so `unit_price` floors to 1 —
	# and at price 1 the `maxi(1, …)` floor collapses both legs, which makes the coin/goods
	# leg inversion arithmetically invisible. `currency_spirit_stone` carries an authored worth
	# and prices at 13, so both directions are exercised for real.
	var stocked := _actor_with(VALUED, 4)
	ItemsApi.inventory(stocked).add(Crafting.resolve(COIN), 1000)
	EconomyApi.attach(stocked)
	var buyer := _actor_with(COIN, 1000)
	EconomyApi.attach(buyer)
	MarketApi.attach(buyer)
	assert_eq(int(EconomyApi.valuation(VALUED)["price"]) > 1, true, "the good is really priced")
	assert_eq(ItemsApi.inventory(buyer).count(VALUED), 0, "the buyer starts with none")

	var bought := MarketApi.buy(stocked, buyer, _rows(VALUED, 2))
	assert_eq(bool(bought["ok"]), true, "the player buys: %s" % bought.get("reason", ""))
	assert_eq(ItemsApi.inventory(buyer).count(VALUED), 2, "and receives the good")

	var sold := MarketApi.sell(null, stocked, buyer, _rows(VALUED, 2))
	assert_eq(bool(sold["ok"]), true, "the player sells: %s" % sold.get("reason", ""))
	assert_eq(ItemsApi.inventory(buyer).count(VALUED), 0, "and gives the good back")
	assert_eq(int(sold["coins"]) < int(bought["coins"]), true, "the shop's spread cost the player")


func test_the_legs_swap_with_the_direction() -> void:
	# Structural, so the inversion cannot come back silently: the goods are on `offer` only
	# when the PLAYER is selling, and the coins only when the shop is.
	var counter := _actor_with(VALUED, 2)
	var seller := _actor_with(VALUED, 2)
	ItemsApi.inventory(counter).add(Crafting.resolve(COIN), 1000)
	ItemsApi.inventory(seller).add(Crafting.resolve(COIN), 1000)
	var from_shop := MarketTransfer.price(counter, seller, _rows(VALUED, 1), true)
	assert_eq(
		String((from_shop["offer"] as Array)[0]["def_id"]),
		String(EconomyValuation.numeraire_id()),
		"a shop sale puts the coins on the offer leg"
	)
	var from_player := MarketTransfer.price(counter, seller, _rows(VALUED, 1), false)
	assert_eq(
		String((from_player["offer"] as Array)[0]["def_id"]),
		String(VALUED),
		"a player sale puts the GOODS on the offer leg"
	)


func test_a_shop_buys_a_good_for_less_than_it_charges() -> void:
	# The end-to-end property, in the direction that would otherwise be exploitable: a player
	# who buys from a shop and immediately sells back must come out behind. The shop is
	# FUNDED — it pays in coins it physically holds, because `exchange` validates both legs
	# against real inventories and an unfunded shop is simply a shop that cannot trade.
	#
	# Trades `VALUED`, not `CHEAP`: at price 1 the two legs collapse and this test would pass
	# with the settlement inverted.
	var shop := _actor_with(VALUED, 10)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 1000)
	EconomyApi.attach(shop)
	var player := _actor_with(COIN, 1000)
	EconomyApi.attach(player)
	MarketApi.attach(player)

	var bought := MarketApi.buy(shop, player, _rows(VALUED, 4))
	assert_eq(bool(bought["ok"]), true, "the purchase settles: %s" % bought.get("reason", ""))
	var paid := int(bought["coins"])
	var sold := MarketApi.sell(null, shop, player, _rows(VALUED, 4))
	assert_eq(bool(sold["ok"]), true, "the resale settles: %s" % sold.get("reason", ""))
	var received := int(sold["coins"])
	assert_eq(received < paid, true, "the player lost %d on a round trip" % (paid - received))


func test_a_shop_cannot_trade_with_itself() -> void:
	# `SAME_ACTOR` is the structural bar: one call can never seat the shop on both sides.
	var shop := _actor_with(CHEAP, 4)
	var result := EconomyApi.trade(shop, shop, _rows(CHEAP, 1), _rows(COIN, 1))
	assert_eq(bool(result["ok"]), false, "a shop cannot trade with itself")
	assert_eq(String(result["reason"]), EconomyExchange.SAME_ACTOR, "and names the rule")


func test_a_shop_that_does_not_buy_refuses_by_content() -> void:
	# Reactivity through refusal, not a price index (ADR 0100). The player HOLDS the good and
	# the shop does not list it, so the only thing that can refuse is the authored policy.
	var def := ShopDef.new()
	def.shop_id = &"black_market"
	def.buys = [&"scroll_rice"]
	var shop := _actor_with(COIN, 100)
	var player := _actor_with(CHEAP, 4)
	EconomyApi.attach(player)
	MarketApi.attach(player)
	var result := MarketApi.sell(def, shop, player, _rows(CHEAP, 1))
	assert_eq(bool(result["ok"]), false, "an unlisted good is not bought")
	assert_eq(String(result["reason"]), MarketApi.SHOP_WILL_NOT_BUY, "and names the refusal")
	assert_eq(ItemsApi.inventory(player).count(CHEAP), 4, "and the player keeps it")


func test_the_coin_count_is_conserved_by_the_commit_loop() -> void:
	# Nothing mints the numeraire: the commit loop removes on one side and delivers on the
	# other, so a round trip can only move the total around.
	var shop := _actor_with(CHEAP, 4)
	ItemsApi.inventory(shop).add(Crafting.resolve(COIN), 100)
	var player := _actor_with(COIN, 100)
	EconomyApi.attach(player)
	MarketApi.attach(player)
	var before := ItemsApi.inventory(player).count(COIN) + ItemsApi.inventory(shop).count(COIN)
	MarketApi.buy(shop, player, _rows(CHEAP, 2))
	MarketApi.sell(null, shop, player, _rows(CHEAP, 2))
	var after := ItemsApi.inventory(player).count(COIN) + ItemsApi.inventory(shop).count(COIN)
	assert_eq(before, after, "the total coin count is unchanged by a buy-then-sell")


func test_an_unfunded_shop_cannot_buy_from_a_player() -> void:
	# When the PLAYER sells, the shop is the payer — and `exchange` validates both legs
	# against real inventories, so a shop holding no coins refuses. Naming it here turns a
	# deep `not_carried` into a readable game rule.
	var shop := _actor_with(CHEAP, 1)
	EconomyApi.attach(shop)
	var player := _actor_with(COIN, 100)
	ItemsApi.inventory(player).add(Crafting.resolve(GOOD), 1)
	EconomyApi.attach(player)
	MarketApi.attach(player)
	var result := MarketApi.sell(null, shop, player, _rows(GOOD, 1))
	assert_eq(bool(result["ok"]), false, "an unfunded shop refuses to buy")
	assert_eq(String(result["reason"]), MarketApi.SHOP_CANNOT_PAY, "and says so")
	assert_eq(ItemsApi.inventory(player).count(GOOD), 1, "and nothing moved")


func _actor_with(def_id: StringName, quantity: int) -> Actor:
	var actor := Actor.new()
	actor.id = &"trader"
	ItemsApi.attach(actor)
	ItemsApi.inventory(actor).add(Crafting.resolve(def_id), quantity)
	return actor


func _rows(def_id: StringName, quantity: int) -> Array:
	return [{"def_id": String(def_id), "quantity": quantity}]
