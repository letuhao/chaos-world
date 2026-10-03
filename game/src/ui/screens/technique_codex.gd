class_name TechniqueCodexScreen
extends UiScreen

## The technique codex: every technique this hero has learned, permanently, with no
## slot limit anywhere on the page. A pure consumer of the `techniques` facade — it
## reads `TechniquesApi.summary`/`inspect` and names nothing else in the module.
##
## **Read-only, and explicitly not the loadout.** ADR 0053 makes the codex and the
## equipped set two different sizes answering two different questions: this screen
## answers "what does this hero know", `technique_loadout` answers "what is bound
## right now". So this one publishes no picker, no equip and no unequip, and its own
## header says so — a codex that offered to equip would collapse the separation the
## module exists to keep.
##
## Contract: `summary()` is the testable surface, with each row's own summary
## nested under `entries`. `{}` with no actor.

## Rows the scene mounts. The pool is grown at runtime rather than truncated: a
## codex that quietly dropped a technique would read as content the hero does not
## have, which is the opposite of what it is for.
const ENTRY_ROWS := 8
const ENTRY_SCENE := "res://src/ui/panels/technique_entry_row.tscn"
const HEADER_TEXT := "Known for good. This is the codex, not the loadout."
const NO_ACTOR_TEXT := "No hero bound."

var _live: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _entry_box: VBoxContainer = null
var _bound: bool = false
var _rows: Array = []


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	# A caller may read `summary()` before the first `refresh()`, so the rows are
	# fed here too — otherwise a child's summary would report whatever the last
	# refresh left behind.
	_read_and_feed()
	var entries := _row_summaries()
	return {
		"actor": String(_actor.id),
		"read_only": true,
		"is_loadout": false,
		"realm_tier": int(_live.get("realm_tier", 0)),
		"codex_count": int(_live.get("codex_count", 0)),
		"equipped_count": int(_live.get("equipped_count", 0)),
		"slot_total": int(_live.get("slot_total", 0)),
		"slot_free": int(_live.get("slot_free", 0)),
		"suspended": _strings(_live.get("suspended", [])),
		"entries": entries,
		"entry_ids": _ids_of(entries),
		"equipped_entry_ids": _ids_where(entries, "equipped"),
		"row_count": _rows.size(),
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
	_footer.text = (
		"Read-only: nothing here is equipped, and nothing here can be lost. "
		+ "Equipping lives on the loadout screen."
	)


# --- ScreenStack hooks ------------------------------------------------------


## Nothing here is pressable, so the landing spot is the first learned technique —
## the thing the codex is read for. Recorded first, because a node outside a
## viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for row in _rows:
		if row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return


## Nothing here is actionable, so nothing is consumed: `ui_cancel` stays free for
## `ScreenStack` to pop, exactly as on every other read-only screen.
func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%CodexHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_entry_box = get_node_or_null("Layout/Scroll/Codex/Entries") as VBoxContainer
	_bound = _header != null and _entry_box != null
	if not _bound:
		return
	_rows = _rows_in(_entry_box, ENTRY_ROWS)


## The rows the scene declares, in order, then the ones grown at runtime.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as TechniqueEntryRow
		if row != null:
			out.append(row)
	while out.size() < extra:
		box.add_child(_new_row(out.size()))
		out.append(box.get_child(box.get_child_count() - 1) as TechniqueEntryRow)
	return out


func _new_row(index: int) -> TechniqueEntryRow:
	var row := load(ENTRY_SCENE).instantiate() as TechniqueEntryRow
	row.name = "Entry%d" % index
	return row


# --- Filling ----------------------------------------------------------------


## The facade snapshot, then one row per codex entry. Each entry is the codex row
## `summary` already publishes, extended with the two fields only `inspect`
## answers: the mastery ladder's reach and what the technique would cost to learn.
## That is the whole codex page — one `inspect` per learned technique, never a
## speculative one, because an unknown id would price something the hero may not
## be able to have yet.
func _read_and_feed() -> void:
	_live = TechniquesApi.summary(_actor) if _actor != null else {}
	_rows_in(_entry_box, (_live.get("entries", []) as Array).size())
	var index := 0
	while index < _rows.size():
		var entry: Dictionary = {}
		if index < (_live.get("entries", []) as Array).size():
			entry = (_live["entries"][index] as Dictionary).duplicate(true)
		_rows[index].call(&"show_entry", _entry_view(entry))
		index += 1


func _entry_view(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var detail := TechniquesApi.inspect(_actor, StringName(entry.get("id", "")))
	var view := entry.duplicate(true)
	# `known`, `equipped`, `grade`, `path` and the rest come from `inspect`, which
	# resolves the technique. The codex row itself only carries id and rung, so
	# without this merge every row reported itself unknown — the row reads
	# `known` and the summary asserted it was true.
	for key in [
		"known",
		"equipped",
		"suspended",
		"grade",
		"path",
		"paths",
		"active",
		"display_name",
		"learn_unmet",
		"equip_unmet",
	]:
		if detail.has(key):
			view[key] = detail[key]
	view["rung_count"] = int(detail.get("rung_count", entry.get("rung_count", 0)))
	view["paths"] = detail.get("paths", [])
	view["learn_price"] = float(detail.get("learn_price", 0.0))
	view["can_learn"] = (detail.get("learn_unmet", []) as Array).is_empty()
	view["learn_unmet"] = _blockers(detail.get("learn_unmet", []))
	return view


## The gate's reason, one label per unmet requirement. The label is the module's
## own wording, so this panel never restates a rule it does not own.
func _blockers(unmet: Array) -> Array:
	var out: Array = []
	for problem in unmet:
		if not problem is Dictionary:
			continue
		var label := String((problem as Dictionary).get("label", ""))
		if not label.is_empty():
			out.append(label)
	return out


# --- Reporting --------------------------------------------------------------


func _row_summaries() -> Array:
	var out: Array = []
	for row in _rows:
		var view: Dictionary = row.call(&"summary")
		if not view.is_empty():
			out.append(view)
	return out


func _ids_of(views: Array) -> Array:
	var out: Array = []
	for entry in views:
		out.append(String((entry as Dictionary).get("id", "")))
	return out


func _ids_where(views: Array, flag: String) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get(flag, false)):
			out.append(String(view.get("id", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
