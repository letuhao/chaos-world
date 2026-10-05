class_name AuctionLotRow
extends PanelContainer

## One lot at an auction, as [method AuctionScreen] publishes it: the frozen price,
## what the next bid must be, who is high, and whether THIS player may bid.
##
## ## The high bid is the row's headline, not its footnote
##
## An auction is a fact about who is winning, and this build has no way to render that
## fact anywhere else — `MarketApi.summary`'s `lots` had no reader. So the high bidder
## and their amount are on the row's own line, and a lot nobody has bid on says so in
## words rather than printing an empty name.
##
## ## It owns every number on the row
##
## `price`, `required_bid`, `high_bid_amount`, `bid_count`, `closes_after` and
## `max_bid` arrive raw and are printed HERE, as AGENTS.md's UI standard requires:
## "no number formatting in a screen — the panel owns `%d/%d`, decimals and widths."
##
## ## `{}` is the FIRST state, not a blank row
##
## `show_lot({})` is a spare row in the pool that no lot occupies: it clears, hides
## and reports `{}`. A lot that EXISTS but is not open still renders, because "not
## open" is a state a player reads and not an absence.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when unfilled.

signal bid_requested(lot_id: String)

## Stands in for a lot the read model does not name. A word, never a dash.
const NO_LOT_TEXT := "No lot here"
## What a lot with nobody on it says. A word, never "0" — a zero bidder count reads
## as a measured fact rather than as an absence.
const NO_HIGH_TEXT := "No bids yet"
## What the high bidder's line reads when there IS one.
const HIGH_TEXT := "High: %s at %d"
## "closes in 3 periods" — the module's word for time (`AuctionState.closes_after`),
## so the row uses it rather than inventing a unit.
const CLOSES_TEXT := "closes in %d periods"
## "seller: shop_x". An auction house lists through the market, so the seller is
## often a counter rather than a person.
const SELLER_TEXT := "seller: %s"
const META_SEP := " · "

var _view: Dictionary = {}
var _head: String = ""
var _state_line: String = ""
var _high_line: String = ""
var _meta: String = ""
var _head_label: Label = null
var _state_label: Label = null
var _high_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one lot as [method AuctionScreen] publishes it. An EMPTY dictionary is
## ADR 0083's FIRST state — no lot is on this row — so the row clears itself and
## hides.
func show_lot(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_state_line = ""
		_high_line = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	_head = String(_view.get("def_id", ""))
	if _head == "":
		_head = String(_view.get("lot_id", ""))
	if _head == "":
		_head = NO_LOT_TEXT
	_state_line = _state_text()
	_high_line = _high_text()
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_lot({})


## Everything the row shows, primitives only. `{}` when no lot is on this row.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"lot_id": lot_id(),
		"def_id": String(_view.get("def_id", "")),
		"seller_id": String(_view.get("seller_id", "")),
		"rarity": String(_view.get("rarity", "")),
		"status": String(_view.get("status", "")),
		# The three numbers an auction is read for: what it is frozen at, what the
		# next bid must be, and what is currently standing.
		"price": int(_view.get("price", 0)),
		"required_bid": int(_view.get("required_bid", 0)),
		"high_bid_amount": int(_view.get("high_bid_amount", 0)),
		"high_bid": String(_view.get("high_bid", "")),
		"bid_count": int(_view.get("bid_count", 0)),
		"closes_after": int(_view.get("closes_after", 0)),
		"open": is_open(),
		"mine": is_mine(),
		"can_bid": can_bid(),
		"bid_disposition": String(_view.get("bid_disposition", "")),
		# The row's OWN sentences.
		"head": _head,
		"state_line": _state_line,
		"high_line": _high_line,
		"meta": _meta,
		"focus_target": "AuctionLotRow",
	}


## Whether a lot is ON this row. An authored lot nobody may bid on answers true and
## renders; a spare row in the pool answers false and does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether this lot is still open for bids. A lot that closed is still ON the row
## and still readable — it says `sold` / `unsold` — because "the auction is over" is
## a fact a player reads, not an absence.
func is_open() -> bool:
	return is_filled() and String(_view.get("status", "")) == AuctionScreen.STATUS_OPEN


## Whether the bound player is the seller. `MarketApi.bid` refuses `seller_is_bidder`,
## so the row must say so rather than offering a button the verb will refuse.
func is_mine() -> bool:
	return is_filled() and bool(_view.get("mine", false))


## Whether the bound player may bid on this lot right now: the lot is open, it is not
## theirs, the bid seam is bound, and the purse covers the required bid. All four are
## computed by the facade or the seam — this row only reports their conjunction, so a
## control is never live where the verb refuses.
func can_bid() -> bool:
	return is_filled() and is_open() and not is_mine() and bool(_view.get("can_bid", false))


## The lot this row offers, or `""` when the row is empty.
func lot_id() -> String:
	return String(_view.get("lot_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


## The press is a REQUEST, never a bid. The row emits the lot id it was built with
## and the screen asks the composition root's seam, so the one place a bid is placed
## is the `app/` type the screen may not name.
func request_bid() -> bool:
	if not can_bid():
		return false
	bid_requested.emit(StringName(lot_id()))
	return true


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent, and every connect guarded.
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_high_label = get_node_or_null("%HighLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_state_label.text = _state_line
	_state_label.theme_type_variation = _state_tone()
	_high_label.text = _high_line
	_meta_label.text = _meta


## "open · bid ≥ 90" or "sold" / "unsold". `required_bid` is the lot's own next legal
## bid, which is what a bidder needs to read before pressing, and it is the same
## number `AuctionState.required_bid` will enforce.
func _state_text() -> String:
	var status := String(_view.get("status", ""))
	if status != AuctionScreen.STATUS_OPEN:
		return status.capitalize()
	return (
		"%s%sbid >= %d"
		% [
			"open",
			META_SEP,
			int(_view.get("required_bid", 0)),
		]
	)


## "High: hero at 210" or "No bids yet". The high bidder's own id, because ADR 0102
## settles bids on a named bidder and a lot with an anonymous leader would be the one
## figure an auction cannot hide.
func _high_text() -> String:
	var high := String(_view.get("high_bid", ""))
	if high == "":
		return NO_HIGH_TEXT
	return HIGH_TEXT % [high, int(_view.get("high_bid_amount", 0))]


## "rarity: rare · closes in 3 periods · seller: shop_x". The rarity and the seller
## are the two facts a bidder cannot otherwise judge, and the closes-in is the lot's
## own `closes_after`, printed in the module's word for time.
func _meta_text() -> String:
	var parts: Array[String] = []
	var rarity := String(_view.get("rarity", ""))
	if rarity != "":
		parts.append("rarity: %s" % rarity)
	var closes := int(_view.get("closes_after", 0))
	if closes > 0:
		parts.append(CLOSES_TEXT % closes)
	var seller := String(_view.get("seller_id", ""))
	if seller != "":
		parts.append(SELLER_TEXT % seller)
	return META_SEP.join(parts)


## An open lot the bound player may not bid on is the quiet card; a lot they may is
## not styled apart here, because the ACTION bar owns the press and this row owns the
## reading. A closed lot is the loud one — the bidding is over.
func _state_tone() -> StringName:
	return &"OkLabel" if is_open() else &"MetaLabel"
