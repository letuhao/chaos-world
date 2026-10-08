class_name SaveScreen
extends UiScreen

## The save menu: every journey, its state, and the two verbs that move it.
##
## ## Why rows name slots the module already bounds
##
## The roster is fixed (ADR 0903): primary plus first/second/third, and no
## slot id ever comes from player text. The screen maps each id to a display
## title of its own — presentation copy, not content — and asks the root for
## one row per id through the list seam. A journey the module does not know
## is reported by name (`unknown_slot`) rather than rendered as a row.
##
## ## Where the verbs come from
##
## `ui/` may not name the `save` module (ADR 0128), so list, load and erase
## all arrive as injected Callables off the composition root (ADR 0143):
## `list_slots() -> Array`, `load_slot(slot) -> Dictionary`,
## `erase_slot(slot) -> Dictionary`. Unwired, every press refuses by name.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}`

const NO_LIST_SEAM := "no_list_seam"
const NO_LOAD_SEAM := "no_load_seam"
const NO_ERASE_SEAM := "no_erase_seam"

## Display titles, in roster order. The ids are the module's; the words are
## this screen's, and a title added here without its row is a label nothing
## shows — the summary pins the pairing.
const TITLES := {
	&"primary": "LOC_UI_SCREENS_595982F5F2",
	&"first": "LOC_UI_SCREENS_9259D34F05",
	&"second": "LOC_UI_SCREENS_2067CC9272",
	&"third": "LOC_UI_SCREENS_B4747AE9F7",
}

var _rows_box: VBoxContainer = null
var _list_slots: Callable = Callable()
var _load_slot: Callable = Callable()
var _erase_slot: Callable = Callable()
var _last_load: Dictionary = {}
var _last_erase: Dictionary = {}


## Inject the three seams. Repaints immediately so a screen bound after its
## first paint does not show the state it had before the binding.
func bind_save(list_slots: Callable, load_slot: Callable, erase_slot: Callable) -> void:
	_list_slots = list_slots
	_load_slot = load_slot
	_erase_slot = erase_slot
	_bind_nodes()
	refresh()


## Whether the page can list anything at all right now.
func can_list() -> bool:
	return _actor != null and _list_slots.is_valid()


## The slot ids on the page, in display order.
func slot_ids() -> Array:
	var out: Array = []
	for row in _slot_rows():
		var slot_id := String((row as SaveSlotRow).slot_id())
		if not slot_id.is_empty():
			out.append(slot_id)
	return out


## Load `slot`: adopt its hero and make its journey live. Returns the root's
## verdict verbatim, then repaints from the root — so what the player sees
## afterwards is the loaded world and not this screen's memory of asking.
func act_load(slot: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null or not _load_slot.is_valid():
		_last_load = {"ok": false, "reason": NO_LOAD_SEAM}
		set_message(NO_LOAD_SEAM, TONE_ERROR)
		refresh()
		return _last_load.duplicate(true)
	_last_load = (_load_slot.call(slot) as Dictionary).duplicate(true)
	if not bool(_last_load.get("ok", false)):
		set_message(String(_last_load.get("reason", NO_LOAD_SEAM)), TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return _last_load.duplicate(true)


## Forget `slot`: delete its files. Returns the root's verdict verbatim.
func act_erase(slot: StringName) -> Dictionary:
	_bind_nodes()
	if _actor == null or not _erase_slot.is_valid():
		_last_erase = {"ok": false, "reason": NO_ERASE_SEAM}
		set_message(NO_ERASE_SEAM, TONE_ERROR)
		refresh()
		return _last_erase.duplicate(true)
	_last_erase = (_erase_slot.call(slot) as Dictionary).duplicate(true)
	if not bool(_last_erase.get("ok", false)):
		set_message(String(_last_erase.get("reason", NO_ERASE_SEAM)), TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return _last_erase.duplicate(true)


## The verdict of the last load, or `{}`. A report, never a selection.
func last_load() -> Dictionary:
	return _last_load.duplicate(true)


## The verdict of the last erase, or `{}`.
func last_erase() -> Dictionary:
	return _last_erase.duplicate(true)


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {
		"list_seam": can_list(),
		"slots": _row_summaries(),
		"slot_ids": slot_ids(),
		"last_load_ok": bool(_last_load.get("ok", false)),
		"last_load_reason": String(_last_load.get("reason", "")),
		"last_erase_ok": bool(_last_erase.get("ok", false)),
		"last_erase_reason": String(_last_erase.get("reason", "")),
	}


func _refresh_view() -> void:
	_bind_nodes()
	if _actor == null or _rows_box == null or not _list_slots.is_valid():
		return
	var rows_data := _list_slots.call() as Array
	var rows := _slot_rows()
	for i in rows.size():
		var row := rows[i] as SaveSlotRow
		if row == null:
			continue
		if i < rows_data.size():
			var view := (rows_data[i] as Dictionary).duplicate(true)
			view["title"] = _title_for(String(view.get("slot", "")))
			row.show_slot(view)
		else:
			row.show_slot({})


func _render() -> void:
	pass


func _bind_nodes() -> void:
	super()
	_rows_box = get_node_or_null("%SlotRows") as VBoxContainer
	for row in _slot_rows():
		var typed := row as SaveSlotRow
		if typed == null:
			continue
		if not typed.load_requested.is_connected(_on_row_load_requested):
			typed.load_requested.connect(_on_row_load_requested)
		if not typed.erase_requested.is_connected(_on_row_erase_requested):
			typed.erase_requested.connect(_on_row_erase_requested)


## Child summaries nested under the rows' own shape, per the screen contract.
func _row_summaries() -> Array:
	var out: Array = []
	for row in _slot_rows():
		var view := (row as SaveSlotRow).summary()
		if view.is_empty():
			continue
		out.append(view)
	return out


## Every slot row under the pool, in display order.
func _slot_rows() -> Array:
	if _rows_box == null:
		return []
	var out: Array = []
	for child in _rows_box.get_children():
		if child is SaveSlotRow:
			out.append(child)
	return out


## The display title for `slot_id`. Presentation copy owned here: the module
## names ids, and words are this screen's.
func _title_for(slot_id: String) -> String:
	return String(TITLES.get(StringName(slot_id), slot_id))


func _on_row_load_requested(slot: StringName) -> void:
	act_load(slot)


func _on_row_erase_requested(slot: StringName) -> void:
	act_erase(slot)
