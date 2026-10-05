class_name AuctionState
extends RefCounted

## The auction ledger: lots, bids, and settlement (ADR 0102).
##
## ## A lot holds the realized instance, not a def id
##
## `Inventory._roll_instance` calls `rng.randomize()` and `_plan` prices off
## `inventory.sample(def_id)` — the FIRST matching stack. A `def_id`-only listing would let a
## seller list a common roll and deliver a legendary one at the frozen low price, which is the
## inflation ADR 0094 closed for base worth. So a lot carries the realized payload and the
## frozen price, and **escrows by removal** at list time.
##
## ## The ledger skeleton is NOT restated here
##
## `empty()` is deliberately a bare `{"lots": {}}` and there is no second `normalize` to go
## with it. The market module owns ONE `module_data` key holding shops, the floor and the
## lots, so an `AuctionState.normalize` that merged `lots` into whatever `MarketState` already
## produced was a second normalizer over a payload another function already owned: it took an
## already-normalized ledger and returned a DIFFERENT, version-less one, and nothing ever
## called it. `MarketState.normalize` folds `lots` itself, which is where the single
## skeleton and the single merge now live (DEF-0222).
##
## ## String keys throughout
##
## `Actor.to_dict` converts only the OUTER `module_data` key, so an inner `StringName` reaches
## the save untouched and breaks every round trip (ADR 0027).

const MODULE_KEY := &"market_state"
const SCHEMA_VERSION := 1

## The authored percent of a bidder's purse one bid step is worth. A percent, not a constant,
## so a 1-coin consumable does not take a 50-coin step (ADR 0102).
const BID_STEP_PERCENT := 10

## The authored percent a lot opens above its own price.
const OPENING_PERCENT := 10

## The default bid ceiling as a percent of a bidder's purse, keyed by a tag on
## `Actor.tags` (ADR 0074). The personality IS the number, and it is authored rather than
## rolled — a bid that varies run to run is a slot machine, not a bid.
const APPETITE_PERCENT := {
	&"opportunist": 30,
	&"thrifty": 45,
	&"collector": 90,
}

## How much of a purse an untagged or unknown-tagged bidder commits. The conservative default:
## an unconfigured bidder under-bids rather than clearing a lot it cannot pay for.
const DEFAULT_APPETITE_PERCENT := 30


## The auction ledger's OWN slice: lots only. Deliberately NOT a whole ledger — the market
## module owns ONE `module_data` key holding shops, the floor and the lots, so an `empty()`
## that invented its own top-level keys would be a second skeleton fighting the first over one
## payload. `MarketState.normalize` folds this container in.
static func empty() -> Dictionary:
	return {"lots": {}}


## The lot at `lot_id`, or `{}`.
static func lot(state: Dictionary, lot_id: StringName) -> Dictionary:
	var found = (state["lots"] as Dictionary).get(String(lot_id))
	return (found as Dictionary) if found is Dictionary else {}


## The next bid that may legally be placed on `lot`: the opening for a first bid, otherwise
## the high plus a step proportional to the LOT's own price. All three numbers come from the
## one formula plus authored percents (ADR 0102).
static func required_bid(lot: Dictionary) -> int:
	var price := maxi(1, int(lot.get("price", 1)))
	var step := maxi(1, roundi(float(price) * float(BID_STEP_PERCENT) / 100.0))
	var high := int(lot.get("high_bid_amount", 0))
	if high <= 0:
		return price + maxi(1, roundi(float(price) * float(OPENING_PERCENT) / 100.0))
	return high + step


## The price a lot opens at. One formula, one place: the lot's own frozen price plus the same
## authored percent the step uses.
static func opening_bid(lot: Dictionary) -> int:
	var price := maxi(1, int(lot.get("price", 1)))
	return price + maxi(1, roundi(float(price) * float(OPENING_PERCENT) / 100.0))


## What this bidder can commit: their purse times their authored appetite. **Never random** —
## same purse, same tag, same lot always produces the same ceiling.
static func bid_ceiling(purse: int, tags: Array) -> int:
	var appetite := DEFAULT_APPETITE_PERCENT
	for tag in tags:
		if APPETITE_PERCENT.has(StringName(tag)):
			appetite = int(APPETITE_PERCENT[StringName(tag)])
			break
	return maxi(0, roundi(float(maxi(0, purse)) * float(appetite) / 100.0))
