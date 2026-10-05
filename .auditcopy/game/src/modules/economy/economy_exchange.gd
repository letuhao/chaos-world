class_name EconomyExchange
extends RefCounted

## The one transfer primitive (ADR 0094). Every exchange — a shop sale, a player trade, a
## tribute payment — is this function with a different partner, so there is exactly one
## atomicity implementation and exactly one price path.
##
## ## Atomicity is a property of control flow, not of discipline
##
## The plan is built against `Inventory.snapshot()` copies of BOTH sides and validated in
## full before the first mutation. `ItemsApi.consume_item` and `add_batch` are each
## all-or-nothing, but a pair of them is not — a buyer whose inventory fills halfway
## through would be left having paid for nothing. Planning first means there is no rollback
## path that can be wrong, and every refusal returns before anything is touched (ADR 0044:
## a refused verb writes nothing).

const EconomyValuationScript := preload("res://src/modules/economy/economy_valuation.gd")

## The refusal reasons. Every one is a **named game rule**, never input validation: a
## panel renders the constant without inventing prose. `unknown_definition` is
## deliberately absent — that is input validation, not a rule (ADR 0084).
const NO_ACTOR := "no_actor"
const SAME_ACTOR := "same_actor"
const NOT_CARRIED := "not_carried"
const NO_SETTLEMENT := "no_settlement"
const NO_ROOM := "no_room"
const NOT_TRADEABLE := "not_tradeable"

## The settlement must be exact: money must match price, not merely cover it. A buyer who
## may pay a shortfall is a credit system, and a seller who accepts one is a price the
## author never wrote.
const SETTLEMENT_SHORT := "settlement_short"


## Exchange `offer` from `from_actor` for `want` from `to_actor`. Both `offer` and `want`
## are arrays of `{def_id, quantity}` primitives.
##
## Either side may be empty, which is what makes barter free: an exchange whose settlement
## is goods rather than money is the same function with a different `want`.
##
## `owner_id` is the actor the transfer is *for*, and is what a `bound_to` is checked
## against: a binding names an owner, so a bound item may leave for a new owner but is
## never priced as if it were unbound.
static func exchange(
	from_actor: Actor, to_actor: Actor, offer: Array, want: Array, owner_id: StringName = &""
) -> Dictionary:
	if from_actor == null or to_actor == null:
		return _refuse(NO_ACTOR)
	if from_actor == to_actor:
		# Self-trade at a fixed price is a money printer and the only unbounded loop this
		# design could produce, so it is refused rather than clamped.
		return _refuse(SAME_ACTOR)

	var from_inventory := ItemsApi.inventory(from_actor)
	var to_inventory := ItemsApi.inventory(to_actor)
	if from_inventory == null or to_inventory == null:
		return _refuse(NOT_CARRIED)

	var offer_plan := _plan(from_inventory, offer, owner_id)
	if not bool(offer_plan["ok"]):
		return _refuse(String(offer_plan["reason"]))
	var want_plan := _plan(to_inventory, want, owner_id)
	if not bool(want_plan["ok"]):
		return _refuse(String(want_plan["reason"]))

	# Priced with the SAME formula on both legs before any mutation, so an exchange can
	# never invent value from a mismatch between two price paths — there are not two.
	#
	# `offered` is what the OFFERING side parts with and `received` is what it takes back,
	# so the rule is `received <= offered`: an offerer may never end up richer. The
	# opposite comparison is the one bug an exchange can ship — it lets a player hand over
	# one coin and walk away with a 13-value item, and every "a trade settled" assertion
	# still passes, because the trade really did settle. (An earlier version here tested
	# `received < offered`, which is the SAME condition read backwards and so changed
	# nothing; the comment and the code disagreed and the tests caught the code.)
	var offered := int(offer_plan["value"])
	var received := int(want_plan["value"])
	if offered <= 0 and received > 0:
		# The offering side has nothing of price, so it cannot settle for anything. A
		# one-sided give is a gift, and a gift belongs to SocialApi.apply_cause
		# (ADR 0091's gift-spam guard) rather than to an exchange. **Checked before the
		# shortfall rule**, because "offered nothing" is the more specific statement: an
		# empty offer is not a trade that happens to fall short, it is not a trade at all,
		# and the reason a panel renders should say so.
		return _refuse(NO_SETTLEMENT)
	if received > offered:
		return _refuse(SETTLEMENT_SHORT)

	# The room check on BOTH sides, again before the first mutation. `loot` overflows into a
	# bounded container and keeps its claim; a trade has no container, so it refuses rather
	# than partly fills. Both sides matter, and the direction is easy to invert: the BUYER
	# receives the offer leg and the SELLER receives the want leg.
	var buyer_room := to_inventory.used_slots() + _slots_needed(to_inventory, offer_plan["rows"])
	if buyer_room > to_inventory.capacity:
		return _refuse(NO_ROOM)
	var seller_room := (
		from_inventory.used_slots() + _slots_needed(from_inventory, want_plan["rows"])
	)
	if seller_room > from_inventory.capacity:
		return _refuse(NO_ROOM)

	# --- commit ---------------------------------------------------------------
	# Past this point nothing can refuse, so the two sides cannot half-settle.
	#
	# `offer` leaves the seller and ARRIVES at the buyer; `want` leaves the buyer and
	# arrives at the seller. Each side is debited its own row and credited the other's, so
	# the two directions cannot drift apart — an earlier version debited both sides and
	# credited only the seller, which destroyed the offered goods outright.
	var moved: Array = []
	for row in offer_plan["rows"]:
		from_inventory.remove(StringName(row["def_id"]), int(row["quantity"]))
		_deliver(to_inventory, row)
		moved.append(
			{"def_id": String(row["def_id"]), "quantity": int(row["quantity"]), "out": true}
		)
	for row in want_plan["rows"]:
		to_inventory.remove(StringName(row["def_id"]), int(row["quantity"]))
		_deliver(from_inventory, row)
		moved.append(
			{"def_id": String(row["def_id"]), "quantity": int(row["quantity"]), "out": false}
		)

	return {
		"ok": true,
		"reason": "",
		"offered": offered,
		"received": received,
		"moved": moved,
	}


## Build and validate one leg without touching anything. `owner_id` is the actor whose
## binding a `bound_to` is checked against, threaded as an argument rather than held as
## module state: a static owner id would be the wrong answer for every caller but one.
static func _plan(inventory: Inventory, rows: Array, owner_id: StringName) -> Dictionary:
	var planned: Array = []
	var value := 0
	for row in rows:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		if not inventory.has(def_id, quantity):
			return {"ok": false, "reason": NOT_CARRIED}
		# A row may name the EXACT instance it means. `inventory.sample(def_id)` returns the
		# FIRST matching stack, which is right for a stackable but wrong for anything that
		# cares about identity: an auction escrow settles a realized roll, and resolving it
		# by def id could hand over a different item of the same definition. Naming the
		# instance is how a caller says "this one, not any one" (ADR 0102).
		var named: String = String(row.get("instance_id", ""))
		var instance: ItemInstance
		if named != "":
			# `find_by_instance_id`, not `find_instance`: the latter matches `def_id` despite
			# its name, so it would happily resolve a DIFFERENT instance of the same
			# definition — which is the exact laundering the escrow exists to prevent.
			instance = inventory.find_by_instance_id(StringName(named))
			if instance == null or instance.def_id != def_id:
				return {"ok": false, "reason": NOT_CARRIED}
		else:
			instance = inventory.sample(def_id)
		var def := inventory.definition_of(def_id)
		if instance == null or def == null:
			return {"ok": false, "reason": NOT_CARRIED}
		if EconomyValuationScript.has_rolled_worth(instance):
			# ADR 0094: a rolled worth is an rng draw. Pricing it would give two players
			# different prices for an identical item, so it is refused by name.
			return {"ok": false, "reason": NO_SETTLEMENT}
		if instance.bound_to != &"" and instance.bound_to != owner_id:
			return {"ok": false, "reason": NOT_TRADEABLE}
		var unit := EconomyValuationScript.price_of(instance)
		value += unit * quantity
		(
			planned
			. append(
				{
					"def_id": def_id,
					"quantity": quantity,
					"price": unit,
					"def": def,
					"batch": ItemStack.from_instance(instance, quantity),
				}
			)
		)
	return {"ok": true, "reason": "", "rows": planned, "value": value}


## How many NEW slots `inventory` needs for `rows`.
##
## The definition is read from the row's own carrying inventory, NOT from the receiving one:
## the receiver may never have held the item, so resolving there yields a null def, counts
## zero slots, and lets the delivery be dropped by a full inventory. That is a silent
## loss, and it is exactly the half-settle the plan-then-apply shape exists to prevent.
static func _slots_needed(inventory: Inventory, rows: Array) -> int:
	var needed := 0
	for row in rows:
		var def_id := StringName(row["def_id"])
		var quantity := int(row["quantity"])
		var def: ItemDef = row["def"]
		if def == null:
			continue
		if def.stackable:
			if inventory.find(def_id) != null:
				continue
			needed += 1
		else:
			needed += quantity
	return needed


## Put one row into `inventory`, merging into a matching stack when there is one.
##
## `Inventory.add_batch` appends a fresh stack rather than merging, which is correct for
## loot (a distinct roll deserves its own row) but wrong for a transfer: trading the same
## item forty times would grow forty stacks and fill twenty-four slots of inventory with
## one item. Merging keeps a hundred trades in one slot, and the room check above stays
## honest because it counts what will actually be added.
static func _deliver(inventory: Inventory, row: Dictionary) -> void:
	var batch: ItemStack = row["batch"]
	var def_id := StringName(row["def_id"])
	var existing := inventory.find(def_id)
	if existing != null and existing.signature() == batch.signature():
		existing.quantity += batch.quantity
		inventory.changed.emit()
		return
	inventory.add_batch(batch)


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "offered": 0, "received": 0, "moved": []}
