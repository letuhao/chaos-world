class_name AuctionReadModel
extends RefCounted

## The auction half of `MarketApi.summary()` (ADR 0102).
##
## ## Why a lot is readable AT ALL
##
## ADR 0102 says "`summary()` reports which lots are due; the caller loops and calls
## `settle_lot`" — and `MarketApi` publishes exactly twelve public methods, which is
## `MAX_FACADE_PUBLIC_METHODS`, so a thirteenth `lot(lot_id)` accessor would fail
## `tools arch`. The read model is therefore where a lot becomes visible, exactly as
## `floor` and `shops` already are: a caller reads the rows and acts through the verbs
## it already has.
##
## ## The lot's own words, not the market's
##
## `required_bid` is `AuctionState.required_bid` and `price` is the frozen number the
## lot was listed at. Both are values the ledger already holds; nothing here prices
## anything, so this file names no weight, no realm curve and no unit price.


## Every lot in `state`, sorted by `lot_id`.
##
## **Sorted, not dictionary order.** The point of ADR 0102 is that the same ledger
## answers the same way twice, and a panel that renders "who is bidding on what" would
## otherwise render insertion order and read a difference where there is none.
static func lots(state: Dictionary) -> Array:
	var out: Array = []
	var lots: Dictionary = state["lots"] as Dictionary
	for lot_id in lots.keys():
		out.append(_row(String(lot_id), lots[lot_id] as Dictionary))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _sort_key(a) < _sort_key(b))
	return out


## One lot as primitives, so a caller never indexes a row it was handed.
static func _row(lot_id: String, lot: Dictionary) -> Dictionary:
	return {
		"lot_id": String(lot.get("lot_id", lot_id)),
		"seller_id": String(lot.get("seller_id", "")),
		"def_id": String(lot.get("def_id", "")),
		"instance_id": String(lot.get("instance_id", "")),
		"rarity": String(lot.get("rarity", "")),
		"realm": String(lot.get("realm", "")),
		"price": int(lot.get("price", 0)),
		"required_bid": AuctionState.required_bid(lot),
		"high_bid": String(lot.get("high_bid", "")),
		"high_bid_amount": int(lot.get("high_bid_amount", 0)),
		"bid_count": (lot.get("bids", {}) as Dictionary).size(),
		"closes_after": int(lot.get("closes_after", 0)),
		"status": String(lot.get("status", "")),
	}


static func _sort_key(row: Dictionary) -> String:
	return String(row.get("lot_id", ""))
