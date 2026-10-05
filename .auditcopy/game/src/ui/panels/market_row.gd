class_name MarketRow
extends PanelContainer

## One shop at a market row, as [method MarketScreen] publishes it: the counter's
## priced shelf, what the shop's purse can pay, and whether THIS player could afford
## the cheapest thing on it.
##
## ## It owns every number on the row
##
## `unit_price`, `coins`, `purse`, `funding` and every `quantity` arrive raw and are
## printed HERE, as AGENTS.md's UI standard requires: "no number formatting in a screen
## — the panel owns `%d/%d`, decimals and widths." The screen hands this row a
## primitives dictionary and formats nothing.
##
## ## `{}` is the FIRST state, not a blank row
##
## `show_shop({})` is a spare row in the pool that no authored shop occupies: it
## clears, hides and reports `{}`. A shop that EXISTS but is not realized reports
## `ok: false` and still renders — the distinction a widget pool makes for free and
## one a collapsed row would throw away.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when unfilled.

## Stands in for a shop the build has not realized. A word, never the id and never a
## dash: an absent counter is a value that is ABSENT, and "-" would read as an
## authored value.
const NO_COUNTER_TEXT := "No counter here"
## "buys" is authored policy, so the row says who it deals with rather than leaving a
## player to discover it by a refusal.
const BUYS_TEXT := "buys %d kinds"
const NO_BUYS_TEXT := "buys nothing"
## The separator between the three segments of the rates line, borrowed from the
## module's own vocabulary so the two rows read the same way.
const META_SEP := " · "

var _view: Dictionary = {}
var _head: String = ""
var _afford_line: String = ""
var _shelf_line: String = ""
var _purse_line: String = ""
var _head_label: Label = null
var _afford_label: Label = null
var _shelf_label: Label = null
var _purse_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one shop as [method MarketScreen] publishes it. An EMPTY dictionary is
## ADR 0083's FIRST state — no shop is on this row — so the row clears itself and
## hides. That is the whole difference between a spare row in a pool and an authored
## but unrealized shop, and it is why the two are not the same call.
func show_shop(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_afford_line = ""
		_shelf_line = ""
		_purse_line = ""
		_render()
		return
	_view = view.duplicate(true)
	_head = String(_view.get("display_name", ""))
	if _head == "":
		_head = String(_view.get("shop_id", ""))
	if _head == "":
		_head = NO_COUNTER_TEXT
	_afford_line = _afford_text()
	_shelf_line = _shelf_text()
	_purse_line = _purse_text()
	_render()


func clear() -> void:
	show_shop({})


## Everything the row shows, primitives only. `{}` when no shop is on this row —
## never a shaped row with empty fields, which is what would make a spare pool row
## and an unrealized shop read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"shop_id": shop_id(),
		"display_name": String(_view.get("display_name", "")),
		"kind": String(_view.get("kind", "")),
		"location_id": String(_view.get("location_id", "")),
		# `ok` is the counter's own verdict: a shop whose id names nothing realized
		# is a shop nothing stocks, and the row must not read as a live stall.
		"realized": bool(_view.get("ok", false)),
		"can_buy": can_buy(),
		"buy_kind_count": _buy_count(),
		"shelf_count": (_view.get("shelf", []) as Array).size(),
		"purse": int(_view.get("purse", 0)),
		"funding": int(_view.get("funding", 0)),
		"cheapest": _cheapest(),
		# The row's OWN sentences, so a test reads the rendered figure and not only
		# the raw number behind it — the half of "the panel owns the format" that a
		# number-only assertion cannot see.
		"head": _head,
		"afford_line": _afford_line,
		"shelf_line": _shelf_line,
		"purse_line": _purse_line,
		"focus_target": "MarketRow",
	}


## Whether a shop is ON this row. An authored shop nobody can trade with answers
## true and renders; a spare row in the pool answers false and does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the bound player could afford the cheapest thing on this shelf right now.
## `ShopCounter.at_location` computes it by comparing the purse to the cheapest
## `sell_total`, which is the same comparison `MarketTransfer.price` makes — so this
## is a read of the real rule, not a second one.
func can_buy() -> bool:
	return is_filled() and bool(_view.get("can_buy", false))


## The shop this row offers, or `""` when the row is empty.
func shop_id() -> String:
	return String(_view.get("shop_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_afford_label = get_node_or_null("%AffordLabel") as Label
	_shelf_label = get_node_or_null("%ShelfLabel") as Label
	_purse_label = get_node_or_null("%PurseLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_afford_label.text = _afford_line
	_afford_label.theme_type_variation = _afford_tone()
	_shelf_label.text = _shelf_line
	_purse_label.text = _purse_line


## "You can afford the cheapest of these" or "Out of reach of the cheapest of these".
## The player's own purse against the shop's cheapest line, both already computed by
## the facade — this row only decides which sentence is true.
func _afford_text() -> String:
	if not bool(_view.get("ok", false)):
		return NO_COUNTER_TEXT
	if (_view.get("shelf", []) as Array).is_empty():
		return "Nothing on the shelf"
	if can_buy():
		return "You can afford the cheapest of these"
	return "Out of reach of the cheapest of these"


## The full priced shelf on one line: "herb ×10 — 24 · pill ×4 — 40". Every figure is
## the facade's own `unit_price` / `coins` / `quantity`, which are the SAME numbers
## `MarketApi.buy` will charge because both read `MarketTransfer.quote`.
func _shelf_text() -> String:
	var rows := _view.get("shelf", []) as Array
	if rows.is_empty():
		return "No stock"
	var parts: Array[String] = []
	for entry in rows:
		var row := entry as Dictionary
		(
			parts
			. append(
				(
					"%s ×%d — %d"
					% [
						String(row.get("def_id", "")),
						int(row.get("quantity", 0)),
						int(row.get("coins", 0)),
					]
				)
			)
		)
	return META_SEP.join(parts)


## "purse 300 · buys 2 kinds" — the shop's own wealth and its authored buy policy,
## both primitives from `ShopCounter.summary`.
func _purse_text() -> String:
	var parts: Array[String] = []
	var purse := int(_view.get("purse", 0))
	parts.append("purse %d" % purse)
	var buys := int(_buy_count())
	parts.append(BUYS_TEXT % buys if buys > 0 else NO_BUYS_TEXT)
	return META_SEP.join(parts)


## The lowest `coins` on the priced shelf, or 0 when nothing is priced. Read, never
## derived: the shelf is already priced by the one facade reader.
func _cheapest() -> int:
	var cheapest := 0
	for entry in _view.get("shelf", []) as Array:
		var coins := int((entry as Dictionary).get("coins", 0))
		if coins <= 0:
			continue
		cheapest = coins if cheapest == 0 else mini(cheapest, coins)
	return cheapest


## How many kinds the shop authors a `buys` list for. Read off the def view the
## facade published, so a black market (`buys: []`) reads as "buys nothing" rather
## than as a shop whose sell button silently refuses.
func _buy_count() -> int:
	var buys := _view.get("buys", []) as Array
	return buys.size()


## A row the player cannot afford from is the quieter card, and an unrealized shop is
## the loudest — it is a control that looks alive and is dead, the shape the UI
## standard exists to prevent.
func _afford_tone() -> StringName:
	if not bool(_view.get("ok", false)):
		return &"WarnLabel"
	return &"OkLabel" if can_buy() else &"MetaLabel"
