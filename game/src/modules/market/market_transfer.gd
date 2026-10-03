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


## Build the two legs for a shop trade.
##
## `trade(player, shop, offer, want)` plans `offer` against the PLAYER and `want` against the
## SHOP, and treats the player as the side whose value must not increase. In every shop trade
## the side paying out value is the player — they hand over coins and receive goods — so the
## coins are the offer leg in BOTH directions and the goods are the want leg.
static func price(
	shop_actor: Actor, player: Actor, rows: Array, shop_is_seller: bool
) -> Dictionary:
	var goods_inventory := ItemsApi.inventory(shop_actor if shop_is_seller else player)
	if goods_inventory == null:
		return {"ok": false, "reason": EconomyExchange.NOT_CARRIED}
	var goods: Array = []
	var coins := 0
	var owner := shop_actor if shop_is_seller else player
	for row in rows:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		if not goods_inventory.has(def_id, quantity):
			return {"ok": false, "reason": EconomyExchange.NOT_CARRIED}
		var instance := goods_inventory.sample(def_id)
		if instance == null:
			return {"ok": false, "reason": EconomyExchange.NOT_CARRIED}
		if instance.bound_to != &"" and instance.bound_to != owner.id:
			return {"ok": false, "reason": EconomyExchange.NOT_TRADEABLE}
		var unit := EconomyValuation.price_of(instance)
		goods.append({"def_id": def_id, "quantity": quantity})
		coins += (
			MarketSpread.sell_total(unit, quantity)
			if shop_is_seller
			else MarketSpread.buy_total(unit, quantity)
		)
	if goods.is_empty() or coins <= 0:
		return {"ok": false, "reason": EconomyExchange.NO_SETTLEMENT}
	# The PAYER must physically hold the coins: the player when the shop sells, the shop when
	# the player sells. Shop funding is a content decision, not a transaction failure.
	var payer := player if shop_is_seller else shop_actor
	var payer_inventory := ItemsApi.inventory(payer)
	if payer_inventory == null or not payer_inventory.has(EconomyValuation.numeraire_id(), coins):
		return {"ok": false, "reason": SHOP_CANNOT_PAY}
	return {
		"ok": true,
		"reason": "",
		"coins": coins,
		"offer": [{"def_id": String(EconomyValuation.numeraire_id()), "quantity": coins}],
		"want": goods,
	}
