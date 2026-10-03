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
static func quote(actor: Actor, offer: Array, partner_id: StringName = &"") -> Dictionary:
	if actor == null:
		return {}
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return {}
	var rows: Array = []
	var total := 0
	var unpriced := 0
	for row in offer:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		var instance := inventory.sample(def_id)
		if instance == null:
			unpriced += 1
			continue
		var unit := EconomyValuation.price_of(instance)
		(
			rows
			. append(
				{
					"def_id": String(def_id),
					"quantity": quantity,
					"unit_price": unit,
					"line_price": unit * quantity,
					"carried": inventory.has(def_id, quantity),
				}
			)
		)
		total += unit * quantity
	return {
		"actor_id": String(actor.id),
		"partner_id": String(partner_id),
		"rows": rows,
		"row_count": rows.size(),
		"total": total,
		"unpriced": unpriced,
		"numeraire": String(EconomyValuation.numeraire_id()),
		"numeraire_price": EconomyValuation.numeraire_price(),
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
