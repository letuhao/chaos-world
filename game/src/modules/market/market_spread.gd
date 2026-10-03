class_name MarketSpread
extends RefCounted

## The one market spread (ADR 0100). A margin lives in the COINS, never in a second price
## function and never as a per-leg rate on the exchange.
##
## ## Why it is not a rate on the numeraire leg
##
## `EconomyExchange`'s settlement rule is `received <= offered` — an offerer may never end up
## richer. When the player sells, the numeraire is the `want` leg and therefore the
## `received` side, so scaling it by any rate above 1 trips `SETTLEMENT_SHORT` on the
## legitimate direction. The rule that closed the arbitrage hole in ADR 0094 also blocks a
## naive margin, which is why this exists rather than a direction-aware parameter on
## `exchange` — that would be the "and" rule, and the ADR 0066 failure in a new place.
##
## ## So the comparison runs on the GOODS, at base price
##
## The coin *quantity* carries the margin; the goods are priced by the one formula. Both
## directions then pass the unmodified guard:
##   shop sells : offered `good x SELL_RATE`, received `good`  ->  good <= good x 1.5
##   player sells: offered `good`,          received `good x BUY_RATE` -> good x 0.5 <= good
##
## Zero lines change in `economy_exchange.gd`. That is the whole point of this file.

## What a shop PAYS for a unit of the one price.
const BUY_RATE := 0.5
## What a shop CHARGES for a unit of the one price.
const SELL_RATE := 1.5


## What a shop pays for `unit_price`. Floored at 1: a shop that paid zero for a good would
## be a hole a player could route value through, and the floor is the same honest answer
## `EconomyValuation.unit_price` gives an unauthored worth.
static func buy_price(unit_price: int) -> int:
	return maxi(1, roundi(float(maxi(1, unit_price)) * BUY_RATE))


## What a shop charges for `unit_price`, likewise floored.
static func sell_price(unit_price: int) -> int:
	return maxi(1, roundi(float(maxi(1, unit_price)) * SELL_RATE))


## The coins for `quantity` units at the buy rate.
static func buy_total(unit_price: int, quantity: int) -> int:
	return buy_price(unit_price) * maxi(0, quantity)


## The coins for `quantity` units at the sell rate.
static func sell_total(unit_price: int, quantity: int) -> int:
	return sell_price(unit_price) * maxi(0, quantity)


## What a player loses by round-tripping one unit through a shop: buying at `SELL_RATE` and
## selling back at `BUY_RATE`. Positive by construction, and asserted by a test rather than
## by this comment.
static func round_trip_cost(unit_price: int) -> int:
	return sell_price(unit_price) - buy_price(unit_price)


## The spread as primitives, for `summary()` so a panel and a test read the invariant from
## one place instead of restating it.
static func view() -> Dictionary:
	return {
		"buy_rate": BUY_RATE,
		"sell_rate": SELL_RATE,
		"round_trip_loss": round_trip_cost(100),
		"arbitrage_possible": BUY_RATE > SELL_RATE,
	}
