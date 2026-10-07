class_name ChannelList
extends VBoxContainer

## One row per meridian, with its state, refinement and injury.
##
## Twenty channels with state, refinement and injury is the richest player-visible
## state in the game, and every cultivation screen used to squash it into a single
## comma-joined Label — a player could not see which channel blocked a gate or
## which was injured (ADR 0043 audit).
##
## Only channels the realm cares about are shown by default; `show_all` lists every
## unlocked channel, so the screen can be quiet in play and complete on demand.
##
## Contract: `summary()` is the testable surface.

signal channel_selected(meridian_id: StringName)

const STATE_ORDER := {
	&"closed": 0,
	&"open": 1,
	&"expanded": 2,
	&"strengthened": 3,
}

var _entries: Array[Dictionary] = []
var _rows: Dictionary = {}
var _required: Array[StringName] = []
var _show_all := false
var _rows_box: VBoxContainer = null
var _header: Label = null
## row -> meridian id, so a press can name what was chosen without a bound Callable per
## render; `_wired` is the once-per-child guard, because the rows are REUSED children.
var _row_owner: Dictionary = {}
var _wired: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Build the list from the actor's meridian network.
## `required` is the set the next realm gates on; those rows are listed first and
## marked, because they are the ones a player has to act on.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	_required.clear()
	for id in state.get("required", []):
		_required.append(StringName(id))
	_show_all = bool(state.get("show_all", false))
	_entries.clear()
	for entry in state.get("channels", []):
		if typeof(entry) == TYPE_DICTIONARY:
			_entries.append(entry)
	_render()


## Report the entries as plain dictionaries: id, name, state, refinement, injured,
## required. `summary()` returns them nested under `channels`, in the same order
## they are rendered, so a caller reading it sees exactly what a player sees.
func summary() -> Dictionary:
	_bind_nodes()
	# A caller may read `summary()` before the first `set_state()` has populated
	# the rows, so render here rather than reporting an empty list.
	if _rows.is_empty() and not _entries.is_empty():
		_render()
	var out: Array = []
	# `_ordered()`, not `_entries`: reporting the raw order while rendering a
	# sorted one would make the contract disagree with the screen.
	for entry in _ordered():
		var meridian_id := StringName(entry.get("id", ""))
		var row: StatRow = _rows.get(meridian_id)
		(
			out
			. append(
				{
					"id": String(entry.get("id", "")),
					"name": String(entry.get("name", entry.get("id", ""))),
					"state": String(entry.get("state", "")),
					"refinement": int(entry.get("refinement", 0)),
					"injured": bool(entry.get("injured", false)),
					"required": _required.has(meridian_id),
					"visible": row != null and row.visible,
					"text": "" if row == null else row.summary().get("label_text", ""),
				}
			)
		)
	return {"channels": out, "required_count": _required.size(), "row_count": _rows.size()}


## Which channels are actually on screen, so a caller can prove the list is not
## silently truncating. In render order.
func visible_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in _ordered():
		var meridian_id := StringName(entry.get("id", ""))
		var row: StatRow = _rows.get(meridian_id)
		if row != null and row.visible:
			out.append(String(meridian_id))
	return out


## Give the pad/keyboard a landing spot on the first required channel, in render
## order, so focus lands where the list actually starts.
func focus_initial() -> void:
	_bind_nodes()
	for entry in _ordered():
		var meridian_id := StringName(entry.get("id", ""))
		if not _required.has(meridian_id):
			continue
		var row: StatRow = _rows.get(meridian_id)
		if row != null and row.visible and row.is_inside_tree():
			row.grab_focus()
			return


## The channels whose id the realm gates on, in gate order.
func required_ids() -> Array[StringName]:
	return _required.duplicate()


## Rank of a channel state, used to sort the least-developed channel first so the
## player is pointed at the one that needs work.
static func state_rank(state: StringName) -> int:
	return int(STATE_ORDER.get(state, -1))


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _rows_box != null:
		return
	_header = get_node_or_null("%HeaderLabel") as Label
	_rows_box = get_node_or_null("%Rows") as VBoxContainer


## Sort: required channels first, then least-developed, so the actionable work is
## always at the top of the list.
func _ordered() -> Array[Dictionary]:
	var out: Array[Dictionary] = _entries.duplicate()
	out.sort_custom(_before)
	return out


func _before(a: Dictionary, b: Dictionary) -> bool:
	var a_req := _required.has(StringName(a.get("id", "")))
	var b_req := _required.has(StringName(b.get("id", "")))
	if a_req != b_req:
		return a_req
	# Least developed first, so the channel with work left is at the top. A rank of
	# -1 (an unrecognised state) sorts ahead of everything, which is the safe
	# direction: an unknown channel is the one a player most needs to look at.
	return state_rank(StringName(a.get("state", ""))) < state_rank(StringName(b.get("state", "")))


## Rows are composed in `channel_list.tscn`, one per meridian, so a row is styled
## by the scene and never built in code (ADR 0038). A mismatch between the row
## count and the channel count is clamped rather than silently padded.
func _render() -> void:
	if _rows_box == null:
		return
	var ordered := _ordered()
	var capacity := _rows_box.get_child_count()
	var index := 0
	while index < capacity and index < ordered.size():
		var row := _rows_box.get_child(index) as StatRow
		var entry: Dictionary = ordered[index]
		var meridian_id := StringName(entry.get("id", ""))
		_rows[meridian_id] = row
		var injured := bool(entry.get("injured", false))
		var required := _required.has(meridian_id)
		# An unknown state means the channel has not been opened at this realm yet.
		# That is not an injury the player can heal, so it must not crowd the list.
		var known := state_rank(StringName(entry.get("state", ""))) >= 0
		row.set_state({"name": _label_for(entry, required, injured), "mode": StatRow.MODE_TEXT})
		row.visible = _show_all or required or (injured and known)
		# Guarded wiring: the rows are reused across renders, so the press handler is
		# connected exactly once per child (AGENTS: every connect is guarded).
		if not _wired.has(row):
			_wired[row] = true
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			row.gui_input.connect(_on_row_gui_input.bind(row))
		_row_owner[row] = meridian_id
		index += 1
	# Any leftover rows from a longer previous render are hidden, never destroyed.
	while index < capacity:
		var extra := _rows_box.get_child(index) as StatRow
		if extra != null:
			extra.visible = false
			extra.set_state({})
		index += 1
	if _header != null:
		_header.text = "Channels (%d shown)" % visible_ids().size()


## A row was pressed: emit the selection. The panel owns only the fact that a row was
## chosen; what a selection MEANS belongs to the screen (ADR 0188: the verb that trains
## one channel needs a production caller, and this press is that player action).
func _on_row_gui_input(event: InputEvent, row: StatRow) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	var meridian_id: StringName = _row_owner.get(row, &"")
	if meridian_id != &"":
		channel_selected.emit(meridian_id)


func _label_for(entry: Dictionary, required: bool, injured: bool) -> String:
	var meridian_id := String(entry.get("id", ""))
	var state := String(entry.get("state", "unknown"))
	var refinement := int(entry.get("refinement", 0))
	var suffix := ""
	if injured:
		suffix = " INJURED"
	elif required:
		suffix = " (required)"
	var name := String(entry.get("name", meridian_id))
	return "%s %s d%d%s" % [name, state, refinement, suffix]
