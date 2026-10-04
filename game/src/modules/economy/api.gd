class_name EconomyApi
extends RefCounted

## Public facade for the `economy` module (ADR 0094). Owns pricing, the one exchange
## primitive, and the versioned trade ledger.
##
## ## There is one price function and one transfer function
##
## `EconomyValuation.unit_price` is the whole of pricing and `EconomyExchange.exchange` is
## the whole of transferring. A shop sale, a player trade and a tribute payment are all the
## same call with a different partner, so there is exactly one atomicity implementation and
## exactly one price path (ADR 0094).
##
## ## `ItemsApi` is frozen and stays frozen
##
## The price input is read the way `LootApi` reads `key_reach`: through
## `ItemsApi.inventory(actor)`, then the def's own `fixed_modifiers`. **No method is added
## to the items facade** — it is at its twelve-method cap and this module was built so it
## never has to be.
##
## ## Reads fold into `summary()`
##
## The facade is capped at twelve public methods, and every read a screen or a sibling
## needs is a key inside `summary()` rather than a thirteenth verb — the `SectApi` and
## `DestinyApi` shape.

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := &"economy_state"
const SCHEMA_VERSION := 1

## Bound trade history. A ledger that grows without a cap is a save that grows without a
## cap, so the history is a ring and says so via `history_truncated`.
const MAX_HISTORY := 32


## Attach the module to `actor`: restore and normalize whatever a prior `Actor.from_dict`
## carried, and stamp the schema version. Idempotent, and safe on an actor who has never
## traded.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := _normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, ledger)


## Exchange `offer` for `want` between two actors. Both are arrays of
## `{def_id, quantity}` primitives; either may be empty, which is what makes barter free.
##
## Returns `{ok, reason, offered, received, moved}` — the `SectApi` result shape, with a
## named constant for every refusal. **A refused exchange writes nothing at all**: the
## whole plan is validated against `Inventory.snapshot()` copies before the first mutation,
## so atomicity is a property of control flow rather than a discipline to be maintained
## (ADR 0044).
static func trade(
	from_actor: Actor, to_actor: Actor, offer: Array, want: Array, owner_id: StringName = &""
) -> Dictionary:
	var result := EconomyExchange.exchange(from_actor, to_actor, offer, want, owner_id)
	if not bool(result.get("ok", false)):
		return result
	_record(from_actor, result)
	return result


## What `offer` is worth right now, without moving anything. The `preview()` the split dev
## cycle requires: the UI builds only against this.
##
## ## `quote` is the ONE row reader, not just one more reader
##
## Every place that must turn `{def_id, quantity}` rows into priced numbers comes through
## here, because a second row loop is a second price path with extra steps (ADR 0094). The
## counterfactual is what this replaced: a shop's shelf, the purse it is minted with and its
## affordability check each walked `def.stock` themselves and each re-decided what a row is —
## which row is carried, which is bound, which has a rolled worth — so the number a panel
## greyed a row out against was produced by code that never met the settlement path.
##
## `ShopCounter` reads its whole priced shelf through here and `MarketTransfer.price` builds
## a trade's two legs through the same helper, so funding, affordance, preview and settlement
## agree by construction rather than by three people reading the same ADR carefully.
##
## `owner_id` is the actor whose `bound_to` a row is checked against, and `&""` applies no
## tradeability rule — a preview shows the whole offer, a transfer is judged for a named
## owner. Threading it is what lets ONE reader serve both without either growing a branch.
##
## A row may also name the exact `instance` it means, the same convention
## `EconomyExchange._plan` reads as `instance_id` and for the same reason: a realized roll
## priced by def id is a different item than the one on the shelf. A `null` actor is allowed
## exactly when every row carries its own realized instance — that is how a merchant prices
## its authored stock before anybody holds it — and a row naming no instance then counts as
## unpriced rather than being silently skipped.
##
## ## This prices BASE only, and that is a boundary, not a gap
##
## The coins a shop charges live in `MarketSpread` (ADR 0100) and `economy` may not name
## `market`. So `quote` returns the base numbers and `MarketTransfer.quote` — which is in
## `market` and may — layers the one spread on top. A margin is never a second price.
static func quote(
	actor: Actor, offer: Array, partner_id: StringName = &"", owner_id: StringName = &""
) -> Dictionary:
	var inventory: Variant = null if actor == null else ItemsApi.inventory(actor)
	if actor != null and inventory == null:
		return {}
	var judged := owner_id != &""
	var priced := _price_rows(inventory, offer, owner_id if judged else null)
	var rows: Array = (priced["rows"] as Array).duplicate(true)
	var total := 0
	var unpriced := 0
	var uncarried := 0
	for row in rows:
		total += int(row["line_price"])
		if bool(row["rolled_worth"]):
			unpriced += 1
		if not bool(row["carried"]):
			uncarried += 1
	return {
		"actor_id": String(actor.id) if actor != null else "",
		"partner_id": String(partner_id),
		"owner_id": String(owner_id),
		"judged": judged,
		"rows": rows,
		"row_count": rows.size(),
		"total": total,
		"unpriced": unpriced,
		"uncarried": uncarried,
		"untradeable": int(priced["untradeable"]),
		"rolled_worth": int(priced["rolled_worth"]),
		"ok": bool(priced["ok"]),
		"numeraire": String(EconomyValuation.numeraire_id()),
		"numeraire_price": EconomyValuation.numeraire_price(),
	}


## Turn `{def_id, quantity}` rows into priced rows. The ONE row reader: [method quote] and
## `MarketTransfer.price` both come here.
##
## `inventory` may be `null` when each row carries its own realized `instance`. `owner_id` is
## the actor whose `bound_to` a row is checked against, or `null` to apply no tradeability
## rule at all. A preview shows a row the caller cannot carry; a transfer refuses the whole
## leg for it, so the refusals are COUNTED rather than thrown and each caller decides what to
## do with them. `ok` is therefore "every row is priced, carried and tradeable" — the answer
## a settler needs and the answer a preview merely reports.
static func _price_rows(inventory: Variant, offer: Array, owner_id: Variant) -> Dictionary:
	var rows: Array = []
	var unpriced := 0
	var uncarried := 0
	var untradeable := 0
	var rolled := 0
	var total := 0
	for row in offer:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		var instance: ItemInstance = row.get("instance")
		if instance == null and inventory != null:
			instance = (inventory as Inventory).sample(def_id)
		if instance == null:
			# An unresolvable row is a refusal for a settler and a missing number for a
			# preview, so it is counted rather than dropped: skipping it silently would let
			# `ok` read true over an offer nothing at all was found in.
			unpriced += 1
			continue
		var carried := inventory != null and (inventory as Inventory).has(def_id, quantity)
		if not carried:
			uncarried += 1
		var tradeable := true
		var has_rolled := false
		if owner_id != null:
			# ADR 0094: a rolled worth is an rng draw, so it is refused by name rather than
			# priced. `MarketTransfer.price` needs this to refuse; a preview needs it to label.
			has_rolled = EconomyValuation.has_rolled_worth(instance)
			if has_rolled:
				rolled += 1
				tradeable = false
			elif instance.bound_to != &"" and instance.bound_to != StringName(owner_id):
				untradeable += 1
				tradeable = false
		var unit := EconomyValuation.price_of(instance)
		total += unit * quantity
		(
			rows
			. append(
				{
					"def_id": String(def_id),
					"quantity": quantity,
					"unit_price": unit,
					"line_price": unit * quantity,
					"carried": carried,
					"tradeable": tradeable,
					"rolled_worth": has_rolled,
				}
			)
		)
	return {
		"rows": rows,
		"total": total,
		"unpriced": unpriced,
		"uncarried": uncarried,
		"untradeable": untradeable,
		"rolled_worth": rolled,
		"ok": unpriced == 0 and uncarried == 0 and untradeable == 0 and rolled == 0,
	}


## The price of one item definition, published read-only so a panel and a test read the
## invariant from one place instead of restating the formula. `{}` when the def is unknown.
static func valuation(def_id: StringName) -> Dictionary:
	var def := Crafting.resolve(def_id)
	if def == null:
		return {}
	var probe := ItemInstance.new(def.id, &"valuation_probe")
	probe.def_ref = def
	probe.rarity = def.rarity
	probe.realm = def.realm
	var base := EconomyValuation.base_worth_of(def)
	return {
		"def_id": String(def.id),
		"display_name": def.display_name,
		"rarity": String(def.rarity),
		"realm": String(def.realm),
		"category": String(def.category),
		"base_worth": base,
		"rarity_weight": EconomyValuation.rarity_weight(def.rarity),
		"realm_factor": RealmRate.factor(def.realm),
		"price": EconomyValuation.price_of(probe),
		"priced": base > 0.0,
	}


## How much of the numéraire `actor` holds. The single settlement number a shop reads.
static func purse(actor: Actor) -> int:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return 0
	return inventory.count(EconomyValuation.numeraire_id())


## The whole read model in one call: holdings, recent trades and the pricing constants a
## panel labels itself with. `{}` when there is no actor — the contract a panel tests
## instead of pixels.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := _normalize(actor.get_module_data(MODULE_KEY))
	var history: Array = (ledger["history"] as Array).duplicate()
	return {
		"actor_id": String(actor.id),
		"numeraire": String(EconomyValuation.numeraire_id()),
		"numeraire_price": EconomyValuation.numeraire_price(),
		"purse": purse(actor),
		"rarity_weights": _rarity_weights(),
		"realm_rate_step": RealmRate.RATE_STEP,
		"history": history,
		"history_count": history.size(),
		"history_truncated": bool(ledger["history_truncated"]),
		"trade_count": int(ledger["trade_count"]),
	}


## The actor's ledger exactly as core persists it, so a caller never reaches into
## `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return _normalize({})
	var ledger := _normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, ledger)
	return ledger


## Content audit: the numéraire must ship, be stackable, carry no roll spec and price at
## exactly 1. A numéraire failing any of those makes every price in the game wrong, so
## this fails loudly rather than shipping a plausible-looking economy.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var def := Crafting.resolve(EconomyValuation.numeraire_id())
	if def == null:
		problems.append(
			"numeraire '%s' is not in the item catalog" % EconomyValuation.numeraire_id()
		)
		return problems
	if not def.stackable:
		problems.append("numeraire '%s' is not stackable" % def.id)
	if not def.roll_spec.is_empty():
		problems.append(
			"numeraire '%s' declares a roll_spec, so its worth would be an rng draw" % def.id
		)
	if def.realm != &"":
		problems.append(
			"numeraire '%s' is realm-stamped, so its price moves on breakthrough" % def.id
		)
	if EconomyValuation.numeraire_price() != 1:
		problems.append(
			"numeraire '%s' prices at %d, expected 1" % [def.id, EconomyValuation.numeraire_price()]
		)
	return problems


static func _record(actor: Actor, result: Dictionary) -> void:
	var ledger := _normalize(actor.get_module_data(MODULE_KEY))
	var history: Array = ledger["history"]
	(
		history
		. append(
			{
				"offered": int(result["offered"]),
				"received": int(result["received"]),
				"moved": (result["moved"] as Array).duplicate(true),
			}
		)
	)
	while history.size() > MAX_HISTORY:
		history.pop_front()
		ledger["history_truncated"] = true
	ledger["history"] = history
	ledger["trade_count"] = int(ledger["trade_count"]) + 1
	actor.set_module_data(MODULE_KEY, ledger)


## The ledger skeleton, authored in exactly one place so a new key cannot be half-written
## by a caller. String keys throughout and no `StringName` anywhere: `Actor.to_dict`
## converts only the OUTER `module_data` key, so an inner `StringName` would reach the
## save untouched and break every round trip.
static func _normalize(data: Variant) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"history": [],
		"history_truncated": false,
		"trade_count": 0,
	}
	if not data is Dictionary:
		return out
	var source := data as Dictionary
	if not (source.get("history", []) as Array).is_empty():
		out["history"] = (source["history"] as Array).duplicate(true)
	out["history_truncated"] = bool(source.get("history_truncated", false))
	out["trade_count"] = maxi(0, int(source.get("trade_count", 0)))
	return out


static func _rarity_weights() -> Dictionary:
	var out := {}
	for rarity in EconomyValuation.RARITY_WEIGHT.keys():
		out[String(rarity)] = EconomyValuation.RARITY_WEIGHT[rarity]
	return out
