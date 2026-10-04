class_name AuctionBids
extends RefCounted

## **NPC bidders at the auction** (ADR 0102, BL-0049).
##
## ## Why this file exists and lives in `app/`
##
## Three constraints meet here and only here:
##
## 1. **`MarketApi` may not name `npc`.** It publishes exactly twelve public methods —
##    `rules.MAX_FACADE_PUBLIC_METHODS` — so a thirteenth verb fails `tools arch`, and
##    `market` declares no `npc` edge in `tools/arch/registry.json`. Adding one would be
##    an undeclared dependency the gate fails on, not a convenience.
## 2. **`npc` may not name `market`** for the mirror reason: `npc` declares
##    `["contracts", "core", "social"]`, and `market -> npc -> market` is a cycle the
##    boundary checker refuses.
## 3. **`Crafting.resolve` is `items` internals** that `modules/*` may not name and
##    `ui/` may not reach. This is the same reason `ForageGranary` exists, and these are
##    the same seam shape.
##
## So the bid decision is composed at the layer that is permitted to depend on
## everything: it takes an **`Actor`**, not an `NpcApi` handle, because an npc *is* an
## `Actor` (ADR 0074/0092) and there is no `NpcActor` type for this to name. That is
## also why this file names no `npc` type at all — the bidding verb needs a wallet and a
## tag list, and both live on core.
##
## ## The number comes from ONE place
##
## `AuctionState.bid_ceiling(purse, tags)` is the ceiling, and it is `market`'s. This file
## does not re-derive it, does not round it and does not scale it. If a second formula
## lived here, ADR 0094's one-price-path rule would have a sibling nobody could see.
##
## ## No rng anywhere in this file
##
## Same purse, same tag, same lot ⇒ same bid, forever. That is what makes an auction
## replayable in a test and is ADR 0102's whole refusal of a "personality roll". The
## structural assertion is `tests/app/test_auction_bids.gd`, which greps this file for
## every seed and generator token Godot offers.

# --- refusals ------------------------------------------------------------------
#
# Named constants rather than prose, so a panel renders the rule it was given and a
# caller can branch on the fact instead of re-deriving it (ADR 0084). Every one of
# these is a refusal that **wrote nothing**.

## The caller's ceiling is below the lot's required bid. This is the ordinary shape of a
## shallow purse meeting a deep good, and it is NOT a failure — it is how a rare lot
## keeps only the bidders it can reach.
const CEILING_BELOW_REQUIRED := "auction_ceiling_below_required"

## The bidder already carries this lot's def. A refusal with teeth: paying for a copy of
## something in your own bag is not a bid, it is a donation with extra steps.
const ALREADY_HOLDS_LOT := "auction_already_holds_lot"

## There is no bid to make — no lot id, or no lot under that id.
const NO_LOT := "auction_no_lot"

## ## The authored appetite a bidder brings to an auction
##
## **The tag table is the answer, and it is already implemented:**
## `AuctionState.APPETITE_PERCENT` reads `opportunist` 30 / `thrifty` 45 / `collector`
## 90 off `Actor.tags` with 30 as the default. `ActorFactory.spawn_npc` copies
## `NpcDef.tags` onto `Actor.tags` verbatim, so an appetite is authored in a `.tres` the
## same way a tier or a realm is — as a tag, read by content, with no roll (ADR 0074).
##
## ### Why no `NpcDef` field and why the three tags are sufficient
##
## A per-def `bid_appetite_percent` field would be a **fourth place the same number can
## live**, and the module that reads it would have to be `npc`, which cannot see
## `market`'s table. Two homes for one appetite is how "the elder bids like a collector"
## becomes a support question: the `.tres` says 90, `APPETITE_PERCENT` says something
## else, and nothing in the build can say which one won. So the table stays the single
## home, `Actor.tags` stays the authored surface, and this file names **no** appetite
## constant of its own.
##
## The three tags are sufficient because appetite is a *willingness to spend a fraction
## of a purse*, and that is one axis with a conservative floor (`DEFAULT_APPETITE_PERCENT`
## 30, so an unconfigured bidder under-bids rather than clearing a lot it cannot pay for).
## A fourth authored row would not be a new behaviour; it would be a re-skin of "willing
## to spend more", which a richer purse already expresses. If the game ever needs
## wealth-class bidders, the correct change is a row in `APPETITE_PERCENT` — authored
## data, in the one table — not a second table.
const APPETITE_TAG_SOURCE := "AuctionState.APPETITE_PERCENT"


## ## The bid verb: an npc, a lot, and what they decide
##
## This is the whole feature. It takes an `Actor` rather than an npc id because ADR
## 0092 settled that an npc *is* an `Actor`, and taking the id would mean this file had
## to resolve through `NpcCatalog` — a `npc` dependency that buys nothing, since the
## decision is made from a purse and a tag list and both are core state.
##
## Returns `{ok, reason, amount, ceiling, required}`:
##
##  - **`ceiling_below_required`** when `AuctionState.bid_ceiling` cannot reach
##    `AuctionState.required_bid`. **No write.** This is the refusal that makes "rare
##    items attract powerful cultivators" arithmetic rather than simulation: a legendary
##    lot prices at `RARITY_WEIGHT`'s 4×, so its opening is 4×, so a shallow purse's
##    ceiling lands below it and the bidder simply does not bid.
##  - **`already_holds_lot`** when the bidder's inventory already carries the lot's def.
##    Also no write.
##  - **`no_lot`** when there is nothing to bid on.
##  - otherwise the **ceiling**, clamped up to the required bid when the ceiling clears
##    it (so a bidder never bids less than the lot accepts) and down to the required bid
##    otherwise (so the bid is always placeable). Either way it is `min(ceiling,
##    required + step)`-safe: the amount is never above the ceiling, because `MarketApi.bid`
##    refuses `bid_above_ceiling` and a void bid would have to be unwound at settlement.
##
## **Time is the caller's.** There is no tick here (DEF-0111): `bid_period` is passed in
## and the module records it, nothing more.
static func bid(npc: Actor, lot_id: StringName, bid_period: int = 0) -> Dictionary:
	if npc == null:
		return _refuse(NO_LOT, 0, 0)
	var lot := _lot(npc, lot_id)
	if lot.is_empty():
		return _refuse(NO_LOT, 0, 0)
	if _holds_lot(npc, lot):
		return _refuse(ALREADY_HOLDS_LOT, 0, AuctionState.required_bid(lot))
	var required := AuctionState.required_bid(lot)
	# **THE number, and the only one.** `EconomyApi.purse` answers wealth because the
	# numeraire prices at exactly 1 (ADR 0094), and `AuctionState.bid_ceiling` is the
	# purse times the authored appetite. Nothing here adjusts it.
	var ceiling := AuctionState.bid_ceiling(EconomyApi.purse(npc), npc.tags)
	if ceiling < required:
		# The refusal that IS the feature. A shallow purse against a deep lot changes
		# nothing at all: no bid row, no ledger write, no event.
		return _refuse(CEILING_BELOW_REQUIRED, ceiling, required)
	# Clamp **up** to `required`: a ceiling that clears the required bid must still meet
	# it, or the bid is refused `bid_too_low` and the bidder under-spends a lot they can
	# afford. Never clamp above the ceiling.
	var amount := maxi(required, ceiling)
	var placed := MarketApi.bid(npc, lot_id, amount, bid_period)
	if not bool(placed.get("ok", false)):
		# The module's own refusal, passed through verbatim — `lot_not_open`,
		# `already_high`, `seller_is_bidder` are all its words, not ours.
		return _refuse(String(placed.get("reason", NO_LOT)), ceiling, required)
	return {"ok": true, "reason": "", "amount": amount, "ceiling": ceiling, "required": required}


## Whether `npc` could afford to bid on `lot_id` right now, without bidding. The read a
## panel asks before it offers a "place bid" affordance: it is the same refusal decision
## with no write at all, so a panel can never show a button the verb will refuse.
static func could_bid(npc: Actor, lot_id: StringName) -> bool:
	if npc == null:
		return false
	var lot := _lot(npc, lot_id)
	if lot.is_empty() or _holds_lot(npc, lot):
		return false
	return (
		AuctionState.bid_ceiling(EconomyApi.purse(npc), npc.tags) >= AuctionState.required_bid(lot)
	)


## The lot at `lot_id` as the read model sees it, or `{}`. **Through `MarketApi.summary`**,
## not `MarketApi.state` — `state` deliberately reads the actor's OWN mirror while
## `summary` goes through the shared world store, and a lot is a world fact (ADR 0101). A
## bidder that could only see the seller's copy would refuse `lot_not_open` on every lot
## in the game.
static func _lot(actor: Actor, lot_id: StringName) -> Dictionary:
	var wanted := String(lot_id)
	for row in MarketApi.summary(actor).get("lots", []) as Array:
		if String((row as Dictionary).get("lot_id", "")) == wanted:
			return row as Dictionary
	return {}


## Whether the bidder's bag already carries the lot's def. Checked on the def, not the
## instance: the lot's `instance_id` was ESCROWED out of the seller's bag at list time, so
## no bidder can be holding *that* instance, and asking the question at all is about not
## buying a second copy of something you own.
static func _holds_lot(actor: Actor, lot: Dictionary) -> bool:
	var def_id := StringName(lot.get("def_id", ""))
	if def_id == &"":
		return false
	var inventory := ItemsApi.inventory(actor)
	return inventory != null and inventory.count(def_id) > 0


static func _refuse(reason: String, ceiling: int, required: int) -> Dictionary:
	return {"ok": false, "reason": reason, "amount": 0, "ceiling": ceiling, "required": required}
