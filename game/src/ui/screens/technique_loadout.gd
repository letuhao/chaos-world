class_name TechniqueLoadoutScreen
extends UiScreen

## The technique loadout: the limited, path-typed slots, what occupies each, and
## the way to release one. A pure consumer of the `techniques` facade — it reads
## `TechniquesApi.summary` and calls `TechniquesApi.unequip`, and names nothing
## else in the module.
##
## This is the other half of ADR 0053. The codex is unbounded and read-only; this
## page is 7 to 10 slots against an unbounded codex, and that gap is the design
## space. So the slot budget is the first thing the page states, and the only
## action here is a release: losing a slot returns the entry to the codex with its
## rung, and no code path here can delete a technique.
##
## Contract: `summary()` is the testable surface, with each slot's own summary
## nested under `slots`. `{}` with no actor.

## Slots the scene mounts. The pool is grown at runtime rather than truncated, so a
## tier's larger budget is never quietly cut down to what the scene happened to
## declare.
const SLOT_ROWS := 7
const SLOT_SCENE := "res://src/ui/panels/technique_slot_row.tscn"
## Concatenated, not one literal: gdformat will not split a string literal, so a
## single 102-char line here fails `gdlint`'s max-line-length for good.
const HEADER_TEXT := (
	"Bound for now. The codex keeps everything; " + "this page decides nothing permanent."
)
const NO_ACTOR_TEXT := "No hero bound."
## The path pools the budget row is stated in, in the facade's own order.
const POOLS := [PathState.QI, PathState.BODY, PathState.MIND, &"universal"]

var _live: Dictionary = {}
var _header: Label = null
var _budget: Label = null
var _slot_box: VBoxContainer = null
var _slot_rows: Array = []
var _bound: bool = false


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	# A caller may read `summary()` before the first `refresh()`, so the rows are
	# fed here too — otherwise a child's summary would report whatever the last
	# refresh left behind.
	_read_and_feed()
	var slots := _row_summaries()
	return {
		"actor": String(_actor.id),
		"is_loadout": true,
		"realm_tier": int(_live.get("realm_tier", 0)),
		"codex_count": int(_live.get("codex_count", 0)),
		"equipped_count": int(_live.get("equipped_count", 0)),
		"slot_total": int(_live.get("slot_total", 0)),
		"slot_free": int(_live.get("slot_free", 0)),
		"suspended": _strings(_live.get("suspended", [])),
		"equipped_ids": _strings(_live.get("equipped_ids", [])),
		"budget_line": _budget_line(),
		"slots": slots,
		"filled_slots": _keys_where(slots, "filled", true),
		"free_slots": _keys_where(slots, "filled", false),
		"pools": _pools(),
		"row_count": _slot_rows.size(),
	}


## Re-read the facade and hand raw values down. The rows own every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	_read_and_feed()


## Repaint this screen's own labels. Each row repaints itself.
func _render() -> void:
	if _header == null:
		return
	_header.text = HEADER_TEXT if _actor != null else NO_ACTOR_TEXT
	if _budget != null:
		_budget.text = _budget_line()


# --- Actions, callable headlessly as well as by the buttons ----------------


## Release one technique's slots. Free, and non-destructive: the entry stays in
## the codex with its rung, so this is a build choice and never a loss.
func act_unequip(technique_id: StringName) -> bool:
	if _actor == null or technique_id.is_empty():
		return false
	var released := TechniquesApi.unequip(_actor, technique_id)
	var ok := bool(released.get("ok", false))
	set_message(
		("Released %s to the codex" % String(technique_id)) if ok else "Not equipped",
		TONE_OK if ok else TONE_ERROR
	)
	refresh()
	return ok


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first release button on a filled slot — the first thing
## a player can actually do here. Recorded first, because a node outside a viewport
## has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for row in _slot_rows:
		if bool(row.call(&"summary").get("can_unequip", false)):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%LoadoutHeader") as Label
	_budget = get_node_or_null("%BudgetLabel") as Label
	_slot_box = get_node_or_null("Layout/Scroll/Loadout/Slots") as VBoxContainer
	_bound = _header != null and _slot_box != null
	if not _bound:
		return
	_slot_rows = _rows_in(_slot_box, SLOT_ROWS)
	for row in _slot_rows:
		var signal_ref: Signal = row.get(&"unequip_requested")
		if not signal_ref.is_connected(_on_unequip):
			signal_ref.connect(_on_unequip)


## The rows the scene declares, in order, then the ones grown at runtime.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as TechniqueSlotRow
		if row != null:
			out.append(row)
	while out.size() < RowBudget.cap(extra):
		box.add_child(_new_row(out.size()))
		out.append(box.get_child(box.get_child_count() - 1) as TechniqueSlotRow)
	return out


func _new_row(index: int) -> TechniqueSlotRow:
	var row := load(SLOT_SCENE).instantiate() as TechniqueSlotRow
	row.name = "Slot%d" % index
	return row


func _on_unequip(technique_id: StringName) -> void:
	act_unequip(technique_id)


# --- Filling ----------------------------------------------------------------


## The facade snapshot, then one row per slot the tier publishes. The budget is
## summed from the slots that are actually there rather than from a second table,
## so the two can never disagree.
func _read_and_feed() -> void:
	_live = TechniquesApi.summary(_actor) if _actor != null else {}
	var views: Array = _live.get("slots", [])
	_grow(views.size())
	var index := 0
	while index < _slot_rows.size():
		var view: Dictionary = {}
		if index < views.size():
			view = (views[index] as Dictionary).duplicate(true)
		_slot_rows[index].call(&"show_slot", view)
		index += 1


func _grow(needed: int) -> void:
	while _slot_rows.size() < maxi(0, needed):
		_slot_box.add_child(_new_row(_slot_rows.size()))
		var row: TechniqueSlotRow = _slot_box.get_child(_slot_box.get_child_count() - 1)
		var signal_ref: Signal = row.get(&"unequip_requested")
		if not signal_ref.is_connected(_on_unequip):
			signal_ref.connect(_on_unequip)
		_slot_rows.append(row)


# --- Reporting --------------------------------------------------------------


## The budget line, built from the raw totals the facade publishes. This screen
## states them and the row states none, so the numbers a player reads are the
## module's own; nothing here is formatted as a technique value.
func _budget_line() -> String:
	if _live.is_empty():
		return ""
	return (
		"%d of %d slots bound at realm tier %d - %d free. The codex holds %d."
		% [
			int(_live.get("equipped_count", 0)),
			int(_live.get("slot_total", 0)),
			int(_live.get("realm_tier", 0)),
			int(_live.get("slot_free", 0)),
			int(_live.get("codex_count", 0)),
		]
	)


## How the budget splits across the path pools, counted from the rows on screen.
func _pools() -> Dictionary:
	var out: Dictionary = {}
	for pool in POOLS:
		out[String(pool)] = {"total": 0, "filled": 0}
	for row in _slot_rows:
		var view: Dictionary = row.call(&"summary")
		var kind := String(view.get("kind", ""))
		if not out.has(kind):
			out[kind] = {"total": 0, "filled": 0}
		var pool_state: Dictionary = out[kind]
		pool_state["total"] = int(pool_state["total"]) + 1
		if bool(view.get("filled", false)):
			pool_state["filled"] = int(pool_state["filled"]) + 1
	return out


func _row_summaries() -> Array:
	var out: Array = []
	for row in _slot_rows:
		var view: Dictionary = row.call(&"summary")
		if not view.is_empty():
			out.append(view)
	return out


func _keys_where(views: Array, flag: String, want: bool = false) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get(flag, false)) == want:
			out.append(String(view.get("slot", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
