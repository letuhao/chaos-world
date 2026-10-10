class_name AnchorConstructionRow
extends PanelContainer

## One anchor the player can raise: what it promises, what it costs, whether this
## body can reach it, and the one button that raises it.
##
## ## What it costs is printed HERE
##
## The coin figure, the item requirement and the `have/need` of each missing item
## belong to this row (AGENTS.md, UI standard). The screen hands down the
## `AnchorApi.summary(actor)` row plus the `cost_of` figure and formats none of it.
##
## ## Refusals are rendered, not hidden
##
## `realm_floor`, `already_raised` and `cannot_afford` are the module's own named
## constants and they are printed on the row verbatim. A player who is told
## `cannot_afford` learns what to do about it; a greyed-out button teaches nothing,
## which is the whole difference between rendering a refusal and hiding a control.
## The button stays LIVE whenever the row is filled, because the refusal is the
## answer and pressing is how a player asks for it.
##
## ## Coins are authored and printed, and NOT charged (ADR 0146)
##
## `AnchorApi.raise_anchor` records the authored coin price and gates on the ITEM
## cost; the purse belongs to `economy`, which `anchor` declares no edge to. So the
## coin figure on this row is the RECORDED price and this row must not describe it
## as settled — the wording says the price, and never that it has been paid.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when the row
## carries no anchor.

## The press. Carries the anchor id ONLY.
signal raise_requested(anchor_id: StringName)

const RAISE_TEXT := "LOC_UI_PANELS_8A418BF331"
const RAISED_TEXT := "LOC_UI_PANELS_2745A2A7B9"
## Wording for the module's own named refusals, kept here beside this row's other
## vocabulary so a caller renders the constant rather than composing prose about it.
const REFUSAL_TEXT := {
	"": "LOC_UI_PANELS_015178DD05",
	"already_raised": "LOC_UI_PANELS_4270FF53DF",
	"cannot_afford": "LOC_UI_PANELS_6892995C3C",
	"realm_floor": "LOC_UI_PANELS_B64550EF50",
	"unknown_anchor": "LOC_UI_PANELS_AF2DAC071D",
	"no_anchor_seam": "LOC_UI_PANELS_8AD66DAB05",
	"no_actor": "LOC_UI_PANELS_78FD30D264",
}
const COIN_TEXT := "LOC_UI_PANELS_2ED4D9295E"
const COIN_TEXT_PLURAL := "LOC_UI_PANELS_DB978840D7"
const ITEM_TEXT := "LOC_UI_PANELS_DDA1409C53"
const MISSING_TEXT := "LOC_UI_PANELS_9F6ED35671"
const NO_ITEMS := "LOC_UI_PANELS_1281D50929"
const REPAIRS_TEXT := "LOC_UI_PANELS_D265FFED4E"
const SHELTERS_TEXT := "LOC_UI_PANELS_359202A634"
const FLOOR_TEXT := "LOC_UI_PANELS_CC45C410E4"
const NO_FLOOR := "LOC_UI_PANELS_1A5685A75E"
const RAISED_MARK := "LOC_UI_PANELS_5F0A197DF2"
const OWE_MARK := "LOC_UI_PANELS_0869D5930F"

var _view: Dictionary = {}
var _cost: Dictionary = {}
var _last_reason: String = ""
var _head: String = ""
var _promise_line: String = ""
var _cost_line: String = ""
var _state_line: String = ""
var _refusal_line: String = ""
var _head_label: Label = null
var _promise_label: Label = null
var _cost_label: Label = null
var _state_label: Label = null
var _refusal_label: Label = null
var _raise_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one anchor. `view` is `AnchorApi.summary(actor)`'s row verbatim plus the
## `cost_of` figure the screen read; an empty dictionary clears the row.
func show_anchor(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_cost = (_view.get("cost", {}) as Dictionary).duplicate(true)
	_head = String(_view.get("display_name", _view.get("id", "")))
	_promise_line = _promise_text()
	_cost_line = _cost_text()
	_state_line = _state_text()
	_refusal_line = _refusal_text()
	_render()


## Show the module's verdict for the last press on this row, verbatim. Kept apart
## from [method show_anchor] so a repaint from the facade cannot erase a refusal the
## player has not read yet — which is exactly what happens if the reason rides only
## in the ledger, where the facade has no memory of it.
func show_refusal(reason: String) -> void:
	_bind_nodes()
	_last_reason = reason
	_refusal_line = _refusal_text()
	_render()


## Clear the outstanding refusal. The only thing a caller can do to one: a refusal
## reports what already happened, so nothing here undoes it.
func clear_refusal() -> void:
	show_refusal("")


## Everything this row shows, primitives only. `{}` when it carries no anchor, so a
## spare row in the pool is not reported as an authored one.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"id": anchor_id(),
		"display_name": String(_view.get("display_name", "")),
		"raised": is_raised(),
		"repairs": bool(_view.get("repairs", false)),
		"shelters": bool(_view.get("shelters", false)),
		"reachable": bool(_view.get("reachable", true)),
		"realm_floor": String(_view.get("realm_floor", "")),
		"repair_per_period": float(_view.get("repair_per_period", 0.0)),
		"raised_integrity": int(_view.get("raised_integrity", 0)),
		"owed": int(_view.get("owed", 0)),
		"cost_coins": int(_cost.get("coins", 0)),
		"missing": _counts(_cost.get("missing", {})),
		"can_raise": can_raise(),
		"last_reason": _last_reason,
		"head": _head,
		"promise_line": _promise_line,
		"cost_line": _cost_line,
		"state_line": _state_line,
		"refusal_line": _refusal_line,
		"raise_label": _button_text(),
	}


## The anchor this row offers, or `""` when the row is empty.
func anchor_id() -> String:
	return String(_view.get("id", ""))


## Whether this anchor already stands in the world. A world fact read from the
## shared ledger (ADR 0146), so a rival's anchor is the same answer.
func is_raised() -> bool:
	return bool(_view.get("raised", false))


## Whether the raise button is a live control. **Raised and unreached both keep it
## LIVE**: the button is how a player asks, and the module's own refusal is the
## answer it deserves to see. Only an empty row and an unwired seam disable it.
func can_raise() -> bool:
	return is_filled() and bool(_view.get("seam", true))


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## Give the keyboard and pad a landing spot. The button when this anchor can be
## raised, so focus lands where a player would act. Recorded first, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _raise_button != null and _raise_button.is_inside_tree():
		_raise_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless runner drives this row before
## a scene tree exists. Idempotent, and the connect guarded.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_promise_label = get_node_or_null("%PromiseLabel") as Label
	_cost_label = get_node_or_null("%CostLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label
	_refusal_label = get_node_or_null("%RefusalLabel") as Label
	_raise_button = get_node_or_null("%RaiseButton") as Button
	if _raise_button != null and not _raise_button.pressed.is_connected(_on_raise):
		_raise_button.pressed.connect(_on_raise)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = L.t(_head)
	_promise_label.text = L.t(_promise_line)
	_cost_label.text = L.t(_cost_line)
	_state_label.text = L.t(_state_line)
	_refusal_label.text = L.t(_refusal_line)
	_refusal_label.visible = not _refusal_line.is_empty()
	_refusal_label.theme_type_variation = &"WarnLabel" if _last_reason != "" else &"MetaLabel"
	_raise_button.disabled = not can_raise()
	_raise_button.text = L.t(_button_text())


## What the anchor DOES, in the two authored shapes ADR 0146 allows: a hearth
## repairs what is already lost, a stone prevents a further loss. They are different
## promises and therefore different authored ids, so the row prints the one its own
## def claims and never implies the other.
##
## `repair_per_period` prints as an integer-per-season figure, with a decimal for a
## fractional rate — because ADR 0146's content gate exists precisely because a
## rate under `1.0` heals nobody over one season, and a fractional rate is the case
## an author needs to see on the page.
func _promise_text() -> String:
	if _view.is_empty():
		return ""
	var parts: Array[String] = []
	if bool(_view.get("repairs", false)):
		parts.append(L.t(REPAIRS_TEXT) % _rate_text(float(_view.get("repair_per_period", 0.0))))
	if bool(_view.get("shelters", false)):
		parts.append(SHELTERS_TEXT)
	if parts.is_empty():
		return String(REFUSAL_TEXT.get("unknown_anchor", "This anchor does nothing."))
	return "  ".join(parts)


## `12.0` reads as `12` and `0.5` as `0.5`, because a rate a player is asked to wait
## a season for must never be rounded down into "nothing happens" on the page.
func _rate_text(rate: float) -> String:
	if not is_finite(rate) or rate < 0.0:
		return L.t("LOC_UI_PANELS_539AEE417B")
	return (
		("%d" % int(roundf(rate)))
		if is_equal_approx(rate, roundf(rate))
		else L.t("LOC_UI_PANELS_16B5D7DF20") % rate
	)


## The price: the authored coin figure and every item requirement, each with what is
## still missing. The coins are the RECORDED price — `raise_anchor` does not debit
## a purse (ADR 0146) — so the wording never claims they were paid.
func _cost_text() -> String:
	if _view.is_empty():
		return ""
	var coins := int(_cost.get("coins", 0))
	var parts: Array[String] = [L.t(COIN_TEXT_PLURAL) % coins if coins > 0 else NO_ITEMS]
	var wanted := _counts(_cost.get("items", {}))
	var missing := _counts(_cost.get("missing", {}))
	for def_id in wanted.keys():
		var need := int(wanted[def_id])
		var short := int(missing.get(def_id, 0))
		var item := L.t(ITEM_TEXT) % [need, def_id]
		parts.append(item if short <= 0 else "%s (%s)" % [item, L.t(MISSING_TEXT) % short])
	return "  ".join(parts)


## Where this anchor stands: raised, raised and how much it has healed, or reachable
## or not against the authored formation floor. The floor is named rather than
## hidden, so a mortal reading `realm_floor` learns what a stone asks of them.
func _state_text() -> String:
	if _view.is_empty():
		return ""
	if is_raised():
		var healed := int(_view.get("raised_integrity", 0))
		return L.t(RAISED_MARK) % healed
	var floor := String(_view.get("realm_floor", ""))
	var line := (
		L.t(FLOOR_TEXT) % floor
		if not floor.is_empty() and not bool(_view.get("reachable", true))
		else L.t(NO_FLOOR)
	)
	var owed := int(_view.get("owed", 0))
	return line if owed <= 0 else "%s  %s" % [line, L.t(OWE_MARK) % owed]


## The module's refusal, verbatim. `""` before any press, so a row nobody has pressed
## says the row is ready rather than showing an empty reason.
func _refusal_text() -> String:
	if _last_reason == "":
		return String(REFUSAL_TEXT.get("", "")) if is_filled() else ""
	return String(REFUSAL_TEXT.get(_last_reason, "Refused: %s" % _last_reason))


func _button_text() -> String:
	if not is_filled():
		return ""
	if not bool(_view.get("seam", true)):
		return String(REFUSAL_TEXT.get("no_anchor_seam", "No raise is wired."))
	return RAISED_TEXT if is_raised() else RAISE_TEXT


## `{def_id: count}` with every count an int, so a JSON hop cannot turn one into a
## float and make two dictionaries that should compare equal stop doing so — the
## `SoulState._trail` reason, applied to a price.
func _counts(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in (value as Dictionary).keys():
		out[String(key)] = int((value as Dictionary)[key])
	return out


## The press is a REQUEST. The row emits the id it was built with; the screen asks
## the composition root's seam, and nothing here writes an anchor ledger.
func _on_raise() -> void:
	var id := anchor_id()
	if id == "" or not can_raise():
		return
	raise_requested.emit(StringName(id))
