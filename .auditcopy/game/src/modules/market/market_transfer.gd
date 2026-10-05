class_name MarketTransfer
extends RefCounted

## The price legs for a shop trade (ADR 0100).
##
## ## Why the margin is a number of COINS
##
## `EconomyExchange`'s rule is `received <= offered` — an offerer may never end up richer.
## When the player sells, the numeraire is the `want` leg and therefore the `received` side,
## so scaling it by any rate above 1 trips `SETTLEMENT_SHORT` on the legitimate direction. The
## rule that closed the arbitrage hole in ADR 0094 also blocks a naive margin.
##
## So the comparison runs on the **goods at base price** and only the coin *quantity* carries
## the spread. Both directions pass the unmodified guard, and **no line of
## `economy_exchange.gd` changes** — which is the whole reason this shape won.

## The refusal when the party that must pay does not hold the coins. Naming it here turns a
## deep `not_carried` from inside the exchange into a readable game rule.
const SHOP_CANNOT_PAY := "shop_cannot_pay"


## The priced read for one side of a shop trade, with the ONE spread applied. Nothing here
## prices: the unit price is `EconomyApi.quote`'s and the margin is `MarketSpread`'s, and
## this function only decides which of the two rates a direction means.
##
## ## Why this lives in `market` and not on `EconomyApi.quote`
##
## `economy` may not name `market` (`registry.json`), so `EconomyApi.quote` cannot reach
## `MarketSpread` and a shop preview had to be written here or written twice. It was written
## twice — the shelf read and the funding arithmetic each rolled their own — and this is the
## one that survives.
##
## `shop_actor` holds the goods when the shop is the seller and `player` holds them when the
## shop is buying, so `shop_is_seller` decides BOTH which inventory is sampled and which rate
## applies. Passing the direction as a bool rather than inferring it is what stops the reader
## and the settler from picking opposite sides of the same trade.
static func quote(
	shop_actor: Actor, player: Actor, rows: Array, shop_is_seller: bool, owner_id: StringName
) -> Dictionary:
	var goods_actor := shop_actor if shop_is_seller else player
	if goods_actor != null and ItemsApi.inventory(goods_actor) == null:
		return {
			"ok": false,
			"rows": [],
			"row_count": 0,
			"coins": 0,
			"shop_is_seller": shop_is_seller,
			"base": 0,
		}
	var priced := EconomyApi.quote(
		goods_actor, rows, StringName(shop_actor.id) if shop_actor != null else &"", owner_id
	)
	# ## The spread is a RATE on the base unit, never a second price
	#
	# `MarketSpread.sell_total(unit, quantity)` rounds PER UNIT and then multiplies, so this is
	# `sell_price(u) * n`, NOT `sell_price(u * n)`. That is why the coins are taken from the
	# one spread function rather than recomputed from `unit_price` here: a `sell_price(total)`
	# would be a silently different shop for every quantity over one.
	var coins := 0
	var priced_rows: Array = []
	for row in priced["rows"] as Array:
		var unit := int(row["unit_price"])
		var quantity := int(row["quantity"])
		var row_coins := (
			MarketSpread.sell_total(unit, quantity)
			if shop_is_seller
			else MarketSpread.buy_total(unit, quantity)
		)
		coins += row_coins
		(
			priced_rows
			. append(
				{
					"def_id": String(row["def_id"]),
					"quantity": quantity,
					"unit_price": unit,
					"coins": row_coins,
					"carried": bool(row["carried"]),
					"tradeable": bool(row["tradeable"]),
				}
			)
		)
	return {
		"ok": bool(priced["ok"]),
		"rows": priced_rows,
		"row_count": priced_rows.size(),
		"coins": coins,
		"shop_is_seller": shop_is_seller,
		"uncarried": int(priced["uncarried"]),
		"untradeable": int(priced["untradeable"]),
		"rolled_worth": int(priced["rolled_worth"]),
		"base": int(priced["total"]),
	}


## Build the two legs for a shop trade.
##
## `trade(player, shop, offer, want)` plans `offer` against the PLAYER and `want` against the
## SHOP, and treats the player as the side whose value must not increase. In every shop trade
## the side paying out value is the player — they hand over coins and receive goods — so the
## coins are the offer leg in BOTH directions and the goods are the want leg.
static func price(
	shop_actor: Actor, player: Actor, rows: Array, shop_is_seller: bool
) -> Dictionary:
	# ## The legs are planned by the SAME reader a shop panel previews with
	#
	# This used to walk `rows` itself and re-derive the coins from `EconomyValuation.price_of`
	# plus `MarketSpread`, which meant the price a player was shown and the price they were
	# charged were two independent readings of the same arithmetic — free to disagree the day
	# one of them gained a clause. It now calls `quote`, which is also what `ShopCounter`
	# reads a shelf through, so the panel and the verb cannot part company.
	var owner := (shop_actor if shop_is_seller else player).id
	var quoted := quote(shop_actor, player, rows, shop_is_seller, owner)
	if not bool(quoted["ok"]):
		# ## The refusal set is UNCHANGED, and the order is the old one
		#
		# A row nobody holds reads `not_carried`; a row bound to somebody else reads
		# `not_tradeable`. A rolled worth also reads `not_carried` here, and that is not a
		# simplification: this verb never priced it, so it never had a name for it. ADR 0094's
		# refusal belongs to `EconomyExchange._plan`, which still runs — it is what turns a
		# rolled good into `no_settlement` at settlement time. Refusing it here too would be a
		# second copy of that rule, which is the thing this change exists to remove.
		return {
			"ok": false,
			"reason":
			(
				EconomyExchange.NOT_TRADEABLE
				if int(quoted["untradeable"]) > 0
				else EconomyExchange.NOT_CARRIED
			),
		}
	var coins := int(quoted["coins"])
	var goods: Array = []
	for row in quoted["rows"] as Array:
		goods.append({"def_id": StringName(row["def_id"]), "quantity": int(row["quantity"])})
	if goods.is_empty() or coins <= 0:
		return {"ok": false, "reason": EconomyExchange.NO_SETTLEMENT}
	# The PAYER must physically hold the coins: the player when the shop sells, the shop when
	# the player sells. Shop funding is a content decision, not a transaction failure.
	var payer := player if shop_is_seller else shop_actor
	var payer_inventory := ItemsApi.inventory(payer)
	if payer_inventory == null or not payer_inventory.has(EconomyValuation.numeraire_id(), coins):
		return {"ok": false, "reason": SHOP_CANNOT_PAY}
	var coins_row := [{"def_id": String(EconomyValuation.numeraire_id()), "quantity": coins}]
	# ## The legs SWAP with the direction, and getting this wrong is invisible at price 1
	#
	# `trade(player, shop, offer, want)` plans `offer` against the PLAYER and `want` against
	# the SHOP, and the guard is `received <= offered`. So:
	#
	#   shop sells : the player hands over COINS and receives GOODS.
	#                offer = coins, want = goods. offered = coins >= received = goods ✔
	#   player sells: the player hands over GOODS and receives COINS.
	#                offer = goods, want = coins. offered = goods >= received = coins ✔
	#
	# Putting the coins on `offer` in BOTH directions is what an earlier version did, and it
	# makes **every player sale of a genuinely-priced good refuse** `settlement_short`: the
	# goods are worth `u` per unit and the coins only `0.5u`, so `received > offered` for any
	# `u >= 2`. It survived because the one end-to-end round-trip test uses an unauthored
	# scroll, whose `unit_price` floors to 1 — where the `maxi(1, …)` floor collapses both
	# legs and the inversion is arithmetically invisible.
	if shop_is_seller:
		return {"ok": true, "reason": "", "coins": coins, "offer": coins_row, "want": goods}
	return {"ok": true, "reason": "", "coins": coins, "offer": goods, "want": coins_row}
