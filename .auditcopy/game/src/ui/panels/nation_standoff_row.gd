class_name NationStandoffRow
extends PanelContainer

## One conflict, as `NationApi.summary(actor)` publishes it under `standoffs`:
## `{standoff_id, other_id, territory_id, mode, quota, closed, outcome, winner_id,
## sides, tributes, prize}`.
##
## ## A conflict is a DECLARATION, and this row shows the declaration
##
## The prize is printed **verbatim from the ledger**, never recomputed here. That is
## the whole point of ADR 0085: the prize was fixed when the two sides declared, so
## a panel that re-derived it would be showing the player a number that was never
## agreed to. Whatever `tribute` says is what pays.
##
## Nothing on this row is a fight. There is no health, no damage, no odds and no
## roll: the tally is how many verdicts have come back from elsewhere, and the
## outcome is what the declared prize paid.
##
## An empty dictionary is ADR 0083's FIRST state (this standoff does not exist): the
## row clears and hides. A closed standoff is NOT that — it exists, it is finished,
## and it renders with its outcome so a player can read what a war cost them.
##
## `summary()` is the testable surface.

const OPEN_TEXT := "Open"
const NO_WINNER := "undecided"
const CLAIMED_OVER := "over"
const NO_PRIZE_TEXT := "no prize declared"
const PRIZE_LABEL := "prize"
const VERDICT_TEXT := "verdicts"

var _view: Dictionary = {}
var _head: String = ""
var _prize: String = ""
var _tally: String = ""
var _outcome: String = ""
var _meta: String = ""
var _head_label: Label = null
var _prize_label: Label = null
var _tally_label: Label = null
var _outcome_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one standoff. An empty dictionary clears and hides the row.
func show_standoff(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_prize = ""
		_tally = ""
		_outcome = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var mode := String(_view.get("mode", ""))
	var territory := String(_view.get("territory_id", ""))
	_head = "%s %s %s" % [mode, CLAIMED_OVER, territory] if territory != "" else mode
	_prize = _prize_text()
	_tally = _tally_text()
	_outcome = _outcome_text()
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_standoff({})


## Everything the row shows, primitives only. `{}` when the standoff does not exist.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	var sides: Dictionary = _view.get("sides", {}) as Dictionary
	var tally := 0
	for side in sides.values():
		tally += int((side as Dictionary).get("won", 0))
	return {
		"standoff_id": String(_view.get("standoff_id", "")),
		"other_id": String(_view.get("other_id", "")),
		"territory_id": String(_view.get("territory_id", "")),
		"mode": String(_view.get("mode", "")),
		"quota": int(_view.get("quota", 0)),
		"closed": bool(_view.get("closed", false)),
		"outcome": String(_view.get("outcome", "")),
		"winner_id": String(_view.get("winner_id", "")),
		"verdicts": tally,
		"sides": _side_summaries(),
		# The DECLARED prize, verbatim. Never recomputed for display.
		"prize_transfer": String((_view.get("prize", {}) as Dictionary).get("transfer", "")),
		"prize_standing": _prize_standing(),
		"head": _head,
		"prize_line": _prize,
		"tally_line": _tally,
		"outcome_line": _outcome,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"outcome_tone": String(_outcome_tone()),
		"card_tone": String(_card_tone()),
		"focus_target": "NationStandoffRow",
	}


## Whether this standoff EXISTS. An open one, a closed one and a spare pool row are
## three different states and only two of them take up space.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the standoff is still running. A closed one is history, not a live claim,
## and the two must not render identically.
func is_open() -> bool:
	return is_filled() and not bool(_view.get("closed", false))


## Whether this standoff ended in a withdrawal. A withdrawal is the exhaustion rule
## at work: a broken side pays and **moves no territory** (ADR 0085).
func is_withdrawal() -> bool:
	return String(_view.get("outcome", "")) == "withdrawal"


func standoff_id() -> String:
	return String(_view.get("standoff_id", ""))


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_prize_label = get_node_or_null("%PrizeLabel") as Label
	_tally_label = get_node_or_null("%TallyLabel") as Label
	_outcome_label = get_node_or_null("%OutcomeLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_tone()
	_prize_label.text = _prize
	_tally_label.text = _tally
	_outcome_label.text = _outcome
	_outcome_label.theme_type_variation = _outcome_tone()
	_meta_label.text = _meta


## An open standoff is the loudest thing on the board: it has a prize at stake and
## somebody contesting it. A closed one is history and reads quietly.
func _card_tone() -> StringName:
	if not is_filled():
		return &"StanceCard"
	return &"OpenStandoffCard" if is_open() else &"ClosedStandoffCard"


func _head_tone() -> StringName:
	return &"SeatLabel" if is_open() else &"MetaLabel"


## A withdrawal is the notable outcome: the war was not won, it was walked away
## from, and the row says which it was rather than flattening both into "closed".
func _outcome_tone() -> StringName:
	if is_withdrawal():
		return &"WarnLabel"
	return &"OkLabel" if bool(_view.get("closed", false)) else &"MetaLabel"


## "prize: ownership · standing +15 / -20". Read straight off the DECLARED prize, so
## the numbers here are the ones both sides agreed to before the first verdict.
func _prize_text() -> String:
	var prize: Dictionary = _view.get("prize", {}) as Dictionary
	var transfer := String(prize.get("transfer", ""))
	if transfer == "":
		return "%s: %s" % [PRIZE_LABEL, NO_PRIZE_TEXT]
	var parts: Array = [transfer]
	var deltas := _prize_standing()
	for side_id in deltas.keys():
		parts.append("%s %+d" % [String(side_id), int(deltas[side_id])])
	return "%s: %s" % [PRIZE_LABEL, ", ".join(parts)]


## "3 / 3 verdicts". The tally is a COUNT of verdicts decided elsewhere — there is no
## roll behind this number and this row refuses to imply one.
func _tally_text() -> String:
	var tally := 0
	var sides: Dictionary = _view.get("sides", {}) as Dictionary
	for side in sides.values():
		tally += int((side as Dictionary).get("won", 0))
	return "%d / %d %s" % [tally, int(_view.get("quota", 0)), VERDICT_TEXT]


func _outcome_text() -> String:
	if is_open():
		return OPEN_TEXT
	var outcome := String(_view.get("outcome", ""))
	var winner := String(_view.get("winner_id", ""))
	if outcome == "":
		return OPEN_TEXT
	return "%s · %s" % [outcome, winner if winner != "" else NO_WINNER]


func _meta_text() -> String:
	return "%s · %s" % [String(_view.get("standoff_id", "")), String(_view.get("other_id", ""))]


func _prize_standing() -> Dictionary:
	var prize: Dictionary = _view.get("prize", {}) as Dictionary
	var deltas: Dictionary = prize.get("standing", {}) as Dictionary
	var out := {}
	for side_id in deltas.keys():
		out[String(side_id)] = int(deltas[side_id])
	return out


func _side_summaries() -> Dictionary:
	var out := {}
	var sides: Dictionary = _view.get("sides", {}) as Dictionary
	for side_id in sides.keys():
		var side: Dictionary = sides[side_id]
		out[String(side_id)] = {
			"won": int(side.get("won", 0)),
			"lost": int(side.get("lost", 0)),
			"exhaustion": float(side.get("exhaustion", 0.0)),
		}
	return out
