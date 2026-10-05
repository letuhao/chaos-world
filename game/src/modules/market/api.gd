class_name MarketApi
extends RefCounted

## Public facade for the `market` module (ADR 0100). Owns shops, the floor, and the spread
## between what a shop pays and what it charges.
##
## ## A margin is a number of coins, not a second price
##
## `EconomyExchange`'s rule is `received <= offered`. When a player sells, the numeraire is
## the `want` leg and therefore the `received` side, so scaling it by a rate above 1 would
## trip `SETTLEMENT_SHORT` on the legitimate direction. `MarketSpread` therefore changes only
## **how many coins move**; the goods are priced by the one formula in `EconomyValuation`
## and **no line of `economy_exchange.gd` changes**. See ADR 0100 for the arithmetic.
##
## ## A shop is an Actor
##
## Because `exchange` takes two Actors, a merchant is an `Actor` carrying an `Inventory` —
## a role tag, not a class (ADR 0092). The items module stays the only item authority, which
## is what `institution_claim.gd:119` demands.
##
## ## A floor item is not a loot overflow
##
## `LootState.world_drops` is a list of *indices into a reward payload*, not holdings: there
## is no independent container and the items only exist while the payload does. A dropped
## item has no encounter, no payload and no claim holder. So the floor is its own bounded
## ledger keyed by location, and it is the only container in this program that **destroys**
## goods on expiry — an asymmetry that is exactly why it must not be `loot`.

const MARKET_KEY := &"market_state"
## The `actor.module_data` key the market ledger persists under (ADR 0027).
const MODULE_KEY := MARKET_KEY
const SCHEMA_VERSION := 1

## Bounded drop container per location. A floor that grows without a cap is a save that grows
## without a cap.
const MAX_FLOOR_PER_LOCATION := 8

## Bounded number of off-stage shops remembered. A refused admit, never a silent trim — the
## `NpcState.ensure_entry` shape.
const MAX_SHOPS := 4

# --- refusals -----------------------------------------------------------------
const NO_LOCATION := "no_location"
const NO_SUCH_DROP := "no_such_drop"
const FLOOR_FULL := "floor_full"
const NO_PERIODS := "no_periods"
const SHOP_WILL_NOT_BUY := "shop_will_not_buy"
const SHOP_CANNOT_PAY := "shop_cannot_pay"

## Bounded open lots (ADR 0102). A refused admit, never a silent trim. Declared with
## the other constants: `gdlint` reads a `const` after a method as out of order.
const MAX_OPEN_LOTS := 16

# --- auction refusals ---------------------------------------------------------
const LOT_UNPRICED := "lot_unpriced"
const LOT_NOT_OPEN := "lot_not_open"
const LOT_NOT_DUE := "lot_not_due"
const LOT_ALREADY_LISTED := "lot_already_listed"
const SELLER_IS_BIDDER := "seller_is_bidder"
const BID_TOO_LOW := "bid_too_low"
const BID_ABOVE_CEILING := "bid_above_ceiling"
const ALREADY_HIGH := "already_high"
const MARKET_FULL := "market_full"

## The shared ledger store, installed by `set_store`. Declared beside its sibling
## rather than below its setter: `gdlint` reads a `var` after a method as out of
## order, and the setter is the only thing that writes it.
static var _store: RefCounted = null

## The auction event bus. **Private and reached through [method _bus] rather than a
## public `events()` accessor**, because this facade already publishes exactly
## `MAX_FACADE_PUBLIC_METHODS` verbs and a thirteenth fails `tools arch` (ADR 0093).
## `AuctionEvents.shared()` is the subscriber's door and hands back the same instance.
static var _events: AuctionEvents = null


## The shared bus this module emits through. One instance for the whole process, so a
## consumer that connected to `AuctionEvents.shared()` hears every lot and never has to
## re-connect per actor.
##
## **Named `_bus` rather than `events()` on purpose.** Two reasons, and the second is the
## one that bit: a static var and a static func cannot share a name, and `_events` held
## both here — so `MarketApi` failed to PARSE and every dependant reported "could not
## resolve class MarketApi" rather than the one line that caused it. Underscore-prefixed
## so it costs nothing against the cap either way.
static func _bus() -> AuctionEvents:
	if _events == null:
		_events = AuctionEvents.shared()
	return _events


## Attach the module to `actor`: restore and normalize whatever a prior `Actor.from_dict`
## carried. Idempotent, and safe on an actor who has traded nothing.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, MarketState.normalize(actor.get_module_data(MODULE_KEY)))


## Install the shared ledger store. **The floor is a world fact, not a per-actor one**: a
## dropped item exists in the location, so the taker must see the dropper's floor. Reading
## `actor.module_data` for it means each actor sees only what they dropped themselves, and
## `take` fails `no_such_drop` for anything another player left.
##
## Same seam and same shape as `HoldingsApi.set_store` (ADR 0101): any object with
## `read_ledger()` and `write_ledger(ledger)`. `attach` still mirrors onto the actor so a
## single-player save carries the floor.
static func set_store(store: RefCounted) -> void:
	_store = store


## Buy `rows` from `shop_actor`. `rows` are `{def_id, quantity}`; the price is the one
## formula's unit price at `SELL_RATE`, so a player-facing price and a settlement price can
## never disagree.
##
## Returns the `EconomyExchange` result plus the coins charged. A refused purchase writes
## nothing on either side — the exchange plans before it mutates.
static func buy(shop_actor: Actor, player: Actor, rows: Array) -> Dictionary:
	if shop_actor == null or player == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	var priced := MarketTransfer.price(shop_actor, player, rows, true)
	if not bool(priced["ok"]):
		return _refuse(String(priced["reason"]))
	var result := EconomyApi.trade(player, shop_actor, priced["offer"], priced["want"], player.id)
	if not bool(result["ok"]):
		return result
	result["coins"] = int(priced["coins"])
	return result


## Sell `rows` to `shop_actor`. Refuses `SHOP_WILL_NOT_BUY` when the def is not in the shop's
## authored `buys` list — which is how a black market is authored rather than priced.
static func sell(shop_def: ShopDef, shop_actor: Actor, player: Actor, rows: Array) -> Dictionary:
	if shop_actor == null or player == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if shop_def != null:
		for row in rows:
			if row is Dictionary and not shop_def.buys_def(StringName(row.get("def_id", ""))):
				return _refuse(SHOP_WILL_NOT_BUY)
	var priced := MarketTransfer.price(shop_actor, player, rows, false)
	if not bool(priced["ok"]):
		return _refuse(String(priced["reason"]))
	var result := EconomyApi.trade(player, shop_actor, priced["offer"], priced["want"], player.id)
	if not bool(result["ok"]):
		return result
	result["coins"] = int(priced["coins"])
	return result


## Drop `rows` onto the floor of `location_id`, **realized at drop time** so a save between
## dropping and taking restores the exact roll. Refuses `FLOOR_FULL` at the per-location cap.
##
## `decay_periods` is AUTHORED at drop time and 0 means never decays. It is a parameter rather
## than something a caller patches afterwards on purpose: `MarketState.normalize` returns a
## copy, so a write-through "set the decay then age it" reads as having worked and has not —
## the entry silently never expires, and the only evidence is a test that waited.
static func drop(
	actor: Actor, location_id: StringName, rows: Array, decay_periods: int = 0
) -> Dictionary:
	if actor == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if location_id == &"":
		return _refuse(NO_LOCATION)
	var state := _state(actor)
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	# `MarketState.drops_at` rather than a raw index: the location key does not exist on a
	# fresh ledger, and `state["floor"][location]` on a missing key is a runtime error rather
	# than an empty list. The first drop into a location must work.
	var entries := MarketState.drops_at(state, location_id)
	if entries.size() + rows.size() > MAX_FLOOR_PER_LOCATION:
		return _refuse(FLOOR_FULL)
	# Plan every row BEFORE the first removal: a drop that half-succeeds leaves goods in one
	# inventory and on the floor (ADR 0044).
	var planned: Array = []
	for row in rows:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		if not inventory.has(def_id, quantity):
			return _refuse(EconomyExchange.NOT_CARRIED)
		var instance := inventory.sample(def_id)
		if instance == null:
			return _refuse(EconomyExchange.NOT_CARRIED)
		if instance.bound_to != &"" and instance.bound_to != actor.id:
			return _refuse(EconomyExchange.NOT_TRADEABLE)
		planned.append({"def_id": def_id, "quantity": quantity, "instance": instance.to_dict()})
	if planned.is_empty():
		return _refuse(EconomyExchange.NOT_CARRIED)
	for entry in planned:
		inventory.remove(StringName(entry["def_id"]), int(entry["quantity"]))
		(
			entries
			. append(
				{
					"drop_id": "drop_%d_%s" % [entries.size(), String(entry["def_id"])],
					"location_id": String(location_id),
					"def_id": String(entry["def_id"]),
					"quantity": int(entry["quantity"]),
					"instance": entry["instance"],
					"dropped_by": String(actor.id),
					"periods_held": 0,
					"decay_periods": maxi(0, decay_periods),
				}
			)
		)
	state["floor"][String(location_id)] = entries
	_save(actor, state)
	return {"ok": true, "reason": "", "dropped": planned.size(), "location_id": String(location_id)}


## Take one entry off the floor into `actor`'s inventory.
##
## First-come: while an entry's `decay_periods` is 0 it never ages, and a plain
## first-come is the honest default. A claim window would be a second time mechanism on top
## of the counter `settle` already needs.
static func take(actor: Actor, location_id: StringName, drop_id: String) -> Dictionary:
	if actor == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	var state := _state(actor)
	var entries: Array = state["floor"].get(String(location_id), [])
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	var found := -1
	for index in entries.size():
		if String((entries[index] as Dictionary).get("drop_id", "")) == String(drop_id):
			found = index
			break
	if found < 0:
		return _refuse(NO_SUCH_DROP)
	var entry: Dictionary = entries[found]
	var instance := ItemInstance.from_dict(entry.get("instance", {}))
	var def := Crafting.resolve(StringName(entry.get("def_id", "")))
	if def == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	instance.def_ref = def
	var batch := ItemStack.from_instance(instance, int(entry.get("quantity", 0)))
	batch.def_ref = def
	# The room check is repeated here because `Inventory` is the only authority on slots and
	# `LootRewards.fits` is unreachable through a facade. It is a room check, not a price
	# formula, so it is not the ADR 0066 duplication.
	if batch.quantity > 0 and inventory.find(def.id) == null and inventory.is_full():
		return _refuse(EconomyExchange.NO_ROOM)
	if batch.quantity > 0:
		inventory.add_batch(batch)
	entries.remove_at(found)
	state["floor"][String(location_id)] = entries
	_save(actor, state)
	return {
		"ok": true,
		"reason": "",
		"def_id": String(def.id),
		"quantity": int(entry.get("quantity", 0))
	}


## Age the floor at `location_id` by `periods`, destroying entries whose `decay_periods`
## has elapsed. **The caller owns time** (DEF-0111): there is no tick here, and an entry with
## `decay_periods == 0` never decays.
static func settle(actor: Actor, location_id: StringName, periods: int) -> Dictionary:
	if actor == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if periods <= 0:
		return _refuse(NO_PERIODS)
	var state := _state(actor)
	var entries: Array = state["floor"].get(String(location_id), [])
	var kept: Array = []
	var expired := 0
	for entry in entries:
		var row := entry as Dictionary
		var decay := int(row.get("decay_periods", 0))
		if decay <= 0:
			kept.append(row)
			continue
		var held := int(row.get("periods_held", 0)) + periods
		if held >= decay:
			expired += 1
			continue
		row["periods_held"] = held
		kept.append(row)
	state["floor"][String(location_id)] = kept
	_save(actor, state)
	return {"ok": true, "reason": "", "expired": expired, "remaining": kept.size()}


## The read model: every shop remembered, the floor at every location, every open lot,
## and the spread a panel labels itself with. `{}` when there is no actor.
##
## **`lots` is here because ADR 0102's settlement loop needs it and this facade is at its
## cap**: the ADR says "summary() reports which lots are due; the caller loops and calls
## settle(seller, lot_id, winner, periods)", and a thirteenth accessor would fail
## `tools arch`. `AuctionReadModel` shapes each row as primitives and answers the two
## questions the caller actually has — `required_bid` and whether it is still `open`.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := _state(actor)
	var drops := 0
	for location_id in (state["floor"] as Dictionary).keys():
		drops += (state["floor"][location_id] as Array).size()
	return {
		"actor_id": String(actor.id),
		"purse": EconomyApi.purse(actor),
		"spread": MarketSpread.view(),
		# The buyer-dependent modifier (ADR 0250). A READ KEY rather than a thirteenth
		# public method, because this facade publishes exactly `rules.MAX_FACADE_PUBLIC_METHODS`
		# verbs and one more fails `tools arch`. The seam itself is `MarketFavour`, named as a
		# class rather than reached through here, for the same reason `AuctionEvents.shared()`
		# is the auction's door instead of an `events()` accessor.
		"favour": MarketFavour.view(),
		"shops": (state["shops"] as Dictionary).keys(),
		"shop_count": (state["shops"] as Dictionary).size(),
		"shop_capacity": MAX_SHOPS,
		"floor": state["floor"],
		"drop_count": drops,
		"floor_capacity_per_location": MAX_FLOOR_PER_LOCATION,
		"lots": AuctionReadModel.lots(state),
		"open_lot_count": _open_lots(state).size(),
		"lot_capacity": MAX_OPEN_LOTS,
	}


## The ids of every lot still open, which is the set a caller owns time over.
static func _open_lots(state: Dictionary) -> Array:
	var out: Array = []
	for row in AuctionReadModel.lots(state):
		if String((row as Dictionary).get("status", "")) == "open":
			out.append(String((row as Dictionary)["lot_id"]))
	return out


## The ledger exactly as core persists it, so a caller never reaches into `module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return MarketState.empty()
	var state := MarketState.normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, state)
	return state


# --- auction (ADR 0102) ------------------------------------------------------
#
# A lot ESCROWS the realized instance by removing it from the seller's inventory at list
# time. That is what stops a `def_id`-only listing, where `inventory.sample(def_id)` returns
# the first matching stack and a seller could list a common roll and deliver a legendary one
# at the frozen low price — the inflation ADR 0094 closed for base worth.


## List `instance_id` for auction. The lot's price is `EconomyValuation.price_of` once, at
## escrow, and **frozen** — it is the reserve, the opening and the step's base.
##
## Refuses `lot_unpriced` for a good with no authored worth (ADR 0094's floor makes it cheap,
## not listable), `already_listed` for a second escrow of one instance, and `market_full` at
## the cap.
static func list(seller: Actor, instance_id: StringName, closes_after_periods: int) -> Dictionary:
	if seller == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if closes_after_periods <= 0:
		return _refuse(NO_PERIODS)
	var inventory := ItemsApi.inventory(seller)
	if inventory == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	var instance := inventory.find_by_instance_id(instance_id)
	if instance == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	var def := inventory.definition_of(instance.def_id)
	if def == null:
		return _refuse(EconomyExchange.NOT_CARRIED)
	if EconomyValuation.has_rolled_worth(instance):
		return _refuse(EconomyExchange.NO_SETTLEMENT)
	if EconomyValuation.base_worth_of(def) <= 0.0:
		return _refuse(LOT_UNPRICED)

	var state := _state(seller)
	var lots := state["lots"] as Dictionary
	if lots.size() >= MAX_OPEN_LOTS:
		return _refuse(MARKET_FULL)
	for lot_id in lots.keys():
		if String((lots[lot_id] as Dictionary).get("instance_id", "")) == String(instance_id):
			return _refuse(LOT_ALREADY_LISTED)

	# Freeze the price BEFORE removing, so a refused write leaves the item where it was.
	var price := EconomyValuation.price_of(instance)
	var lot_id := "lot_%s_%s" % [String(seller.id), String(instance_id)]
	var lot := {
		"lot_id": lot_id,
		"seller_id": String(seller.id),
		"def_id": String(instance.def_id),
		"instance_id": String(instance_id),
		"rolled": (instance.rolled as Array).duplicate(true),
		"rarity": String(instance.rarity),
		"realm": String(instance.realm),
		"signature":
		ItemStack.signature_of(instance.def_id, instance.rarity, instance.realm, instance.rolled),
		"price": price,
		"opening": AuctionState.opening_bid({"price": price}),
		"opened_period": 0,
		"closes_after": closes_after_periods,
		"high_bid_amount": 0,
		"high_bid": "",
		"bids": {},
		"status": "open",
	}
	inventory.remove_instance(instance_id)
	lots[lot_id] = lot
	_save(seller, state)
	return {"ok": true, "reason": "", "lot_id": lot_id, "price": price, "opening": lot["opening"]}


## Place a bid of `amount` on `lot_id`. `bidder_id` names the bidder's wallet; the caller
## resolves it to an `Actor` at settlement, because a bid is a PROMISE and promises outlive
## the room.
##
## Refuses `bid_too_low` unless `amount` strictly exceeds the required bid (which makes ties
## structurally impossible), `bid_above_ceiling` when the amount exceeds what the module
## already knows the bidder could pay, and `already_high` for self-shading.
static func bid(bidder: Actor, lot_id: StringName, amount: int, bid_period: int = 0) -> Dictionary:
	if bidder == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if amount <= 0:
		return _refuse(BID_TOO_LOW)
	var state := _state(bidder)
	var lot := AuctionState.lot(state, lot_id)
	if lot.is_empty():
		return _refuse(LOT_NOT_OPEN)
	if String(lot.get("status", "")) != "open":
		return _refuse(LOT_NOT_OPEN)
	if String(lot.get("seller_id", "")) == String(bidder.id):
		return _refuse(SELLER_IS_BIDDER)
	var required := AuctionState.required_bid(lot)
	if amount < required:
		return _refuse(BID_TOO_LOW)
	var ceiling := AuctionState.bid_ceiling(EconomyApi.purse(bidder), bidder.tags)
	if amount > ceiling:
		# A bid the module already knows is void must not be recorded: exact settlement is
		# the exchange's own rule, and a void bid would have to be unwound at settlement.
		return _refuse(BID_ABOVE_CEILING)
	var bids := lot["bids"] as Dictionary
	if String(bids.get(String(bidder.id), {}).get("bid_id", "")) != "":
		return _refuse(ALREADY_HIGH)
	var bid_id := "bid_%s_%d" % [String(bidder.id), bid_period]
	# The high bidder BEFORE this write, because `outbid_in_auction` has to name who was
	# displaced — and the announcement is emitted after the write, so a consumer that
	# reads the ledger sees the new high rather than the old one.
	var displaced := String(lot.get("high_bid", ""))
	bids[String(bidder.id)] = {
		"bid_id": bid_id,
		"actor_id": String(bidder.id),
		"amount": amount,
		"period": bid_period,
	}
	lot["bids"] = bids
	lot["high_bid_amount"] = amount
	lot["high_bid"] = String(bidder.id)
	_save(bidder, state)
	_bus().bid_placed.emit(String(bidder.id), lot_id, amount, required)
	if displaced != "" and displaced != String(bidder.id):
		# **The displaced bidder is NOT removed from the lot.** They stay in the settlement
		# walk at their OWN bid, which is what makes an outbid a demotion rather than an
		# eviction — and the event says so, because a consumer that read this as a removal
		# would tell a player they had been struck from a sale they are still in.
		_bus().outbid_in_auction.emit(displaced, lot_id, String(bidder.id), amount)
	return {
		"ok": true, "reason": "", "lot_id": String(lot_id), "amount": amount, "required": required
	}


## Close `lot_id` and pay the outcome. **Called by a caller that owns time** (DEF-0111): there
## is no tick here. `winner_actor` is the shop or seller holding the escrow.
##
## Named `settle_lot`, not `settle`, because the floor's aging verb is `settle` and two verbs
## of one name in one file is a **parse error** — invisible until something imports the module,
## and reported as a cascade of "could not resolve class MarketApi" rather than as itself.
##
## Bids are walked in descending order and the first bidder whose purse STILL covers their own
## bid wins — the purse is re-read at settlement, so a caller cannot hand-pick a winner and a
## bidder who spent their money since bidding loses the lot rather than defaulting silently.
static func settle_lot(
	winner_actor: Actor, bidder_of: Callable, lot_id: StringName, periods: int
) -> Dictionary:
	if winner_actor == null:
		return _refuse(EconomyExchange.NO_ACTOR)
	if periods <= 0:
		return _refuse(NO_PERIODS)
	var state := _state(winner_actor)
	var lot := AuctionState.lot(state, lot_id)
	if lot.is_empty():
		return _refuse(LOT_NOT_OPEN)
	if String(lot.get("status", "")) != "open":
		return _refuse(LOT_NOT_OPEN)
	if int(periods) < int(lot.get("closes_after", 1)):
		return _refuse(LOT_NOT_DUE)
	# Order the bids by amount, then by actor id so the walk is deterministic — the same
	# ledger settles the same way twice, which is what makes an auction replayable.
	var ranked: Array = (lot["bids"] as Dictionary).values()
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["amount"]) == int(b["amount"]):
				return String(a["actor_id"]) < String(b["actor_id"])
			return int(a["amount"]) > int(b["amount"])
	)
	for entry in ranked:
		var row := entry as Dictionary
		var bidder: Actor = (
			bidder_of.call(String(row["actor_id"])) if bidder_of.is_valid() else null
		)
		if bidder == null:
			continue
		if EconomyApi.purse(bidder) < int(row["amount"]):
			# Money left between bid and close. Named, visible, consequential: the lot falls
			# to the next bidder at THEIR OWN bid, never to the seller charged a shortfall.
			# Announced per defaulting bidder rather than once at the end, because a lot with
			# three broken promises has three facts and a single "someone defaulted" would
			# not say which. The emission happens BEFORE the next bidder is tried, so a
			# consumer reading the ledger sees the promise still recorded and unfulfilled.
			_bus().defaulted_on_a_bid.emit(String(row["actor_id"]), lot_id, int(row["amount"]))
			continue
		# **Deliver BEFORE marking the lot sold, and set the amount it will charge BEFORE
		# delivering.** The delivery charges `winning_amount`, so it must already be written or
		# the house is credited zero. An earlier version marked the lot sold first and set
		# `winning_amount` after the delivery — which meant a bidder who won a lot received the
		# goods and the house received nothing, and the call still returned `ok: true`. A won
		# lot that delivers nothing is the worst outcome an auction can produce, so on failure
		# the lot stays `open` and the challenge passes to the next bidder: the goods are still
		# escrowed and still owed.
		lot["winning_amount"] = int(row["amount"])
		if not _deliver_lot(winner_actor, bidder, lot):
			continue
		lot["status"] = "sold"
		lot["winner"] = String(row["actor_id"])
		state["lots"][String(lot_id)] = lot
		_save(winner_actor, state)
		# AFTER the save, and after the coins have moved: a subscriber that answers by
		# reading the two purses sees a settled transfer rather than a half-written one.
		_bus().won_auction.emit(
			String(row["actor_id"]), lot_id, int(row["amount"]), String(lot.get("seller_id", ""))
		)
		return {
			"ok": true,
			"reason": "",
			"status": "sold",
			"winner": String(row["actor_id"]),
			"amount": int(row["amount"]),
			"delivered": true,
		}
	lot["status"] = "unsold"
	state["lots"][String(lot_id)] = lot
	_save(winner_actor, state)
	return {"ok": true, "reason": "", "status": "unsold", "winner": "", "amount": 0}


## Pay the winner and hand over the escrowed good.
##
## The lot is **not** moved through `EconomyExchange`: it was removed from the seller's
## inventory at `list` time and its realized payload lives in the ledger, so there is no
## inventory anywhere holding it for an exchange to plan against. The COINS still go through
## `trade`, because that is a real transfer between two real inventories and reusing it is
## what keeps one settlement path.
##
## The room check is repeated here for the same reason `take` repeats it: `Inventory` is the
## only authority on slots, and an auction that cannot deliver a won lot is worse than one
## that never opened.
static func _deliver_lot(winner_actor: Actor, bidder: Actor, lot: Dictionary) -> bool:
	var inventory := ItemsApi.inventory(bidder)
	if inventory == null:
		return false
	var def := Crafting.resolve(StringName(lot.get("def_id", "")))
	if def == null:
		return false
	var instance := (
		ItemInstance
		. from_dict(
			{
				"def_id": String(lot.get("def_id", "")),
				"instance_id": String(lot.get("instance_id", "")),
				"rarity": String(lot.get("rarity", "common")),
				"realm": String(lot.get("realm", "")),
				"rolled": (lot.get("rolled", []) as Array).duplicate(true),
				"durability": 1.0,
				"refinement": 0,
				"bound_to": "",
				"catalog_version": 0,
				"seed": 0,
				"version": ItemInstance.SCHEMA_VERSION,
			}
		)
	)
	instance.def_ref = def
	# **Both legs are checked BEFORE either runs.** An earlier version added the item and
	# then charged the coins — so a bidder who could not pay walked away with the goods, and
	# the lot was marked sold. The room check and the coin leg now both pass first; only then
	# does anything move. There is no rollback here, so the ordering IS the atomicity.
	if not def.stackable and inventory.is_full():
		return false
	# `winning_amount` is set on the row BEFORE this call — the delivery reads the amount it
	# is about to charge. Setting it after the delivery is what an earlier ordering did, and
	# it meant the coin leg charged a ZERO amount: the goods went out, the house received
	# nothing, and the lot reported itself sold.
	var amount := int(lot.get("winning_amount", 0))
	if amount <= 0:
		return false
	var coins := [{"def_id": String(EconomyValuation.numeraire_id()), "quantity": amount}]
	var paid := EconomyApi.trade(bidder, winner_actor, coins, [], bidder.id)
	if not bool(paid.get("ok", false)):
		return false
	var added := inventory.add_instance(instance)
	if added != 0:
		return false
	return true


# --- internals ---------------------------------------------------------------


## Read the ledger, from the shared store when there is one.
##
## The floor, the shops and the auction lots are all WORLD facts (ADR 0101), so a store is
## what makes them visible across actors. Without one the actor's own mirror is used, which is
## correct for a single-holder save and wrong the moment a second party exists — so `attach`
## still mirrors there for the save.
static func _state(actor: Actor) -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return MarketState.normalize(_store.call(&"read_ledger"))
	if actor == null:
		return MarketState.empty()
	return MarketState.normalize(actor.get_module_data(MODULE_KEY))


## Write the ledger to the store when there is one, and always mirror it onto the actor so a
## single-player save still carries the floor.
static func _save(actor: Actor, state: Dictionary) -> void:
	var normalized := MarketState.normalize(state)
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	if actor != null:
		actor.set_module_data(MODULE_KEY, normalized)


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "coins": 0, "offered": 0, "received": 0}
