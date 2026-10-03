class_name MarketState
extends RefCounted

## The market ledger: remembered shops and the floor (ADR 0100).
##
## ## Why the floor is its own container
##
## `LootState.world_drops` is a list of *indices into a reward payload*, not holdings:
## `reclaim` resolves a drop by searching `state["rewards"][encounter]`, there is no
## independent container, and the items only exist while the payload does. A dropped item has
## no encounter, no payload and no claim holder — the claim is the whole difference. So the
## floor is keyed by location and holds realized `ItemInstance` payloads.
##
## ## String keys throughout
##
## `Actor.to_dict` converts only the OUTER `module_data` key, so an inner `StringName`
## reaches the save untouched and breaks every round trip (ADR 0027).

const MODULE_KEY := &"market_state"
const SCHEMA_VERSION := 1


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "shops": {}, "floor": {}, "lots": {}}


## Fold any payload into the current shape. **Starts from `empty()`**, so a fresh ledger always
## carries every container as a real key — a caller that indexes `state["lots"][lot_id]` on a
## new ledger must get a refusal, not a runtime error (ADR 0102).
static func normalize(data: Variant) -> Dictionary:
	var out := empty()
	if not data is Dictionary:
		return out
	var source := data as Dictionary
	var shops = source.get("shops", {})
	if shops is Dictionary:
		for shop_id in (shops as Dictionary).keys():
			out["shops"][String(shop_id)] = (shops as Dictionary)[shop_id].duplicate(true)
	var floor = source.get("floor", {})
	if floor is Dictionary:
		for location_id in (floor as Dictionary).keys():
			var entries: Array = []
			var rows = (floor as Dictionary)[location_id]
			if rows is Array:
				for row in rows:
					if row is Dictionary:
						entries.append((row as Dictionary).duplicate(true))
			out["floor"][String(location_id)] = entries
	# `lots` is owned by `AuctionState` (ADR 0102); this module only carries the key so the
	# skeleton stays in one place and an auction lot round-trips through the same normalize.
	var lots = source.get("lots", {})
	if lots is Dictionary:
		for lot_id in (lots as Dictionary).keys():
			var lot = (lots as Dictionary)[lot_id]
			if lot is Dictionary:
				out["lots"][String(lot_id)] = (lot as Dictionary).duplicate(true)
	return out


## The entries at `location_id`, or an empty array. Never a shared reference: the caller
## mutates what it gets back, and a shared array would write through into the ledger.
static func drops_at(state: Dictionary, location_id: StringName) -> Array:
	var entries = (state["floor"] as Dictionary).get(String(location_id))
	return (entries as Array) if entries is Array else []
