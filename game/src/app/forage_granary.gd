class_name ForageGranary
extends RefCounted

## The item-granting half of the `gather` route, installed into `ForageApi.set_granter`
## by [method EconomyBoot.install]. Wiring and ONE conversion, and nothing else.
##
## ## Why this half lives in `app/` and not in a module
##
## `forage` declares `["contracts", "core", "holdings"]` and **no `items` edge**, and that
## is not a simplification — it is the only legal shape. `ItemsApi` is at its twelve-method
## cap (`rules.MAX_FACADE_PUBLIC_METHODS`), so no "resolve a def by id" verb can be added to
## it, and `Crafting.resolve` is `items` internals that `tools arch` fails on unless the
## referrer is `app/`. `holdings` may not name `ItemsApi` at all. So the one piece of the
## route that needs an `ItemDef` is supplied by the composition root, which is permitted to
## depend on everything by construction — ADR 0002's dependency inversion, enforced by the
## gate rather than asserted in a comment. This is the `CustodyApi.set_minter` adapter
## shape verbatim: the SEAM stays a `Callable`, only the vocabulary changes.
##
## ## There is ONE item-granting system and this reuses it
##
## `Inventory.add(def, quantity)` is the same call `Crafting.craft_with` makes for a recipe
## output, and it is the only way a stack enters a bag anywhere in `game/src`. Nothing here
## rolls, mints or prices anything: a gathered unit is an ordinary stack of an ordinary
## authored `ItemDef`, so a forage and a craft of the same item are indistinguishable to the
## bag, the save and the economy. A second item-granting path is the thing this file exists
## to avoid.
##
## ## The probe is the atomicity, and it is why `forage` can afford no items edge
##
## Called with `probe = true` this answers how many units COULD be delivered and moves
## nothing, by adding onto an `Inventory.snapshot()` — which is a deep copy, so the probe
## cannot touch the real bag even by mistake. That is what lets `ForageApi.harvest` refuse
## a full bag BEFORE `accrue` charges upkeep and spends condition: the caller pays nothing
## for a delivery that could not happen.
##
## ## Why the "does this item exist" question lives here
##
## `forage`'s yield table names item ids, and an id that is not in the item catalog is a
## content gap. Resolving it needs `Crafting.resolve`, which needs this layer. So `known`
## is answered by the same function that grants, and `forage` treats a false answer as
## "this node yields nothing" — named, not silent.

## Answered when the item id names no authored `ItemDef`. `forage` surfaces this as
## `no_yield_content`, so a stale content id is a named refusal rather than an empty bag.
const UNKNOWN_ITEM := "unknown_item"
## The bag has no room. `probe = true` reports this; the real grant path cannot reach it
## because the probe reserved the space first.
const BAG_FULL := "bag_full"
## No inventory is attached to the actor at all. Distinct from a full bag: an actor with no
## `items` module has no bag to be full.
const NO_INVENTORY := "no_inventory"


## Deliver `quantity` units of `item_id` to `actor`, or report how many could be delivered.
##
## Called with `probe = true` this is a pure read — it reports capacity against a snapshot
## copy and never writes. Called with `probe = false` it adds, and returns how many units
## actually landed so a caller can refuse a short delivery rather than call it a success.
static func deliver(actor: Actor, item_id: StringName, quantity: int, probe: bool) -> Dictionary:
	var def := Crafting.resolve(item_id)
	if def == null:
		return _answer(false, UNKNOWN_ITEM, 0, false)
	if actor == null:
		# A null actor is a caller asking what the item IS, not who gets it.
		return _answer(quantity > 0, "" if quantity > 0 else UNKNOWN_ITEM, 0, true)
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return _answer(false, NO_INVENTORY, 0, true)
	if quantity <= 0:
		# A zero-quantity probe is the "is this item real" question and the answer is yes.
		return _answer(true, "", 0, true)
	if probe:
		return _answer(true, "", _fits(inventory, def, quantity), true)
	# `Inventory.add` returns the LEFTOVER that did not fit, not the number it accepted —
	# `return remaining` over `_add_batch`/`_add_instances`. Reading it as an acceptance
	# count inverts every branch below: a bag with room returns 0 left over and reads as
	# `BAG_FULL`, so a harvest that fit perfectly refused with nothing delivered. The
	# subtraction is the whole fix, and it is why the real grant can be checked against the
	# probe's promise instead of against the author's guess at the return value.
	var leftover := inventory.add(def, quantity)
	if leftover <= 0:
		return _answer(true, "", quantity, true)
	# The count is `quantity - leftover`, NOT zero, and that is the whole point of measuring
	# the leftover at all. `ForageApi.harvest` reads `granted` and names a partial delivery
	# `grant_short` rather than `grant_refused`, so a caller can render "63 of 66 arrived"
	# instead of a bare refusal -- and it can only tell the two apart if the granter says
	# which one happened. Reporting zero here would make every short harvest indistinguishable
	# from one that delivered nothing.
	return _answer(false, BAG_FULL, maxi(0, quantity - leftover), true)


## How many units of `def` the bag could still take, measured against a COPY.
##
## `Inventory.snapshot()` is a real copy rather than a view, so `add` onto it cannot reach
## the live bag. That is the whole atomicity claim: if the probe says the units fit, the
## grant that follows cannot fail for want of space — and because [method deliver] measures
## the leftover the same way the probe does, the two agree by construction rather than by
## two call sites remembering the same convention.
static func _fits(inventory: Inventory, def: ItemDef, quantity: int) -> int:
	var copy := inventory.snapshot()
	var leftover := maxi(0, copy.add(def, quantity))
	return maxi(0, quantity - leftover)


static func _answer(ok: bool, reason: String, granted: int, known: bool) -> Dictionary:
	return {"ok": ok, "reason": reason, "granted": maxi(0, granted), "known": known}
