class_name TechniqueEquipPicker
extends PanelContainer

## The unbound half of the loadout: every technique the hero has learned that no
## slot holds, each with a button that binds it.
##
## This panel answers "what can I equip" — the question the codex cannot, because
## ADR 0053 makes the codex read-only and the loadout the only page that decides a
## binding. It publishes no rule either: `equip_requested` carries the technique id
## and the screen asks `TechniquesApi.equip`, so no pick here can ever become a
## learn and no release here can become a loss.
##
## The panel owns every format it shows, so a screen never renders a number.
##
## Contract: `summary()` is the testable surface. `{}` when it carries nothing.

signal equip_requested(technique_id: StringName)

## Rows the scene mounts; the pool grows to fit a codex larger than that.
const OFFER_ROWS := 4
const OFFER_SCENE := "res://src/ui/panels/technique_equip_row.tscn"
const NOTHING_LEFT := "Every technique you know is already bound."
const NOTHING_KNOWN := "No technique learned yet."

var _entries: Array = []
var _rows: Array = []
var _row_box: VBoxContainer = null
var _empty_label: Label = null
var _row_scene: PackedScene = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Offer these techniques as bindable. Each entry is one `TechniquesApi.inspect`
## view — identity, `path`, `grade`, `active`, `equipped`, `claimable_slots`,
## `equip_unmet` — passed raw. An empty array clears the offer, which is what the
## scene's spare rows show.
func show_entries(entries: Array) -> void:
	_bind_nodes()
	_entries = entries.duplicate(true)
	_feed()
	_render()


## Read the offer straight off a `TechniquesApi.summary` snapshot, so the screen
## hands this panel the ONE dictionary it already holds instead of re-walking the
## codex itself. One `inspect` per LEARNED entry, never a speculative one: the offer
## IS the codex, so an id the hero does not hold is not on it, and an id the catalog
## cannot resolve is skipped rather than rendered as an empty row.
func show_snapshot(snapshot: Dictionary, actor: Actor) -> void:
	if actor == null or snapshot.is_empty():
		show_entries([])
		return
	var resolved: Array = []
	for raw in snapshot.get("entries", []) as Array:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var technique_id := StringName(String(entry.get("id", "")))
		if technique_id.is_empty():
			continue
		var detail := TechniquesApi.inspect(actor, technique_id)
		if detail.is_empty():
			continue
		detail["equipped"] = bool(entry.get("equipped", false))
		resolved.append(detail)
	show_entries(resolved)


func clear() -> void:
	show_entries([])


## Everything this panel shows, primitives only, each row's own summary nested
## under `rows`. `{}` when it carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if not _bound:
		return {}
	var rows := _row_summaries()
	return {
		"offered": rows.size(),
		"offered_ids": _ids_where(rows, "offered"),
		"equipable": _ids_where(rows, "can_equip"),
		"has_open_slots": int(rows.size()) > 0,
		"empty_text": _empty_text(),
		"rows": rows,
		"row_count": _rows.size(),
	}


## The landing spot is the first binding this offer can actually make.
func focus_initial() -> void:
	_bind_nodes()
	for row in _rows:
		if bool((row.call(&"summary") as Dictionary).get("can_equip", false)):
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true
	_row_box = get_node_or_null("%OfferBox") as VBoxContainer
	_empty_label = get_node_or_null("%EmptyLabel") as Label
	if _row_box == null:
		return
	_row_scene = load(OFFER_SCENE) as PackedScene
	_rows = _rows_in(_row_box, OFFER_ROWS)


## The rows the scene declares, in order, then the ones grown at runtime.
func _rows_in(box: VBoxContainer, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as TechniqueEquipRow
		if row != null:
			out.append(row)
	# `extra` is a codex-derived count and every row is a live Control, so the bound
	# is snapshotted through RowBudget rather than read back off the array we grow.
	var target := RowBudget.cap(extra)
	while out.size() < target:
		box.add_child(_new_row(out.size()))
		out.append(box.get_child(box.get_child_count() - 1) as TechniqueEquipRow)
	return out


func _new_row(index: int) -> TechniqueEquipRow:
	var row := _row_scene.instantiate() as TechniqueEquipRow
	row.name = "Offer%d" % index
	return row


func _grow(needed: int) -> void:
	if _row_box == null:
		return
	while _rows.size() < RowBudget.cap(maxi(0, needed)):
		_row_box.add_child(_new_row(_rows.size()))
		var row: TechniqueEquipRow = _row_box.get_child(_row_box.get_child_count() - 1)
		var signal_ref: Signal = row.get(&"equip_requested")
		if not signal_ref.is_connected(_on_equip):
			signal_ref.connect(_on_equip)
		_rows.append(row)


func _on_equip(technique_id: StringName) -> void:
	equip_requested.emit(technique_id)


# --- Filling ----------------------------------------------------------------


func _feed() -> void:
	_grow(_entries.size())
	var index := 0
	while index < _rows.size():
		var view: Dictionary = {}
		if index < _entries.size():
			view = (_entries[index] as Dictionary).duplicate(true)
		_rows[index].call(&"show_entry", view)
		index += 1


func _render() -> void:
	if _empty_label == null:
		return
	_empty_label.text = _empty_text()
	_empty_label.visible = _entries.is_empty()


## What a player sees when the offer is empty: no codex at all reads differently
## from a codex whose every entry is already bound, because the two want different
## next moves — learn one, or change a binding.
func _empty_text() -> String:
	if _entries.is_empty():
		return NOTHING_KNOWN
	var offers := 0
	for entry in _entries:
		if _offerable(entry as Dictionary):
			offers += 1
	return NOTHING_LEFT if offers > 0 else NOTHING_KNOWN


## A learned entry is offerable when it holds no slot and the module says one is
## claimable. Both halves are the module's own answer, never this screen's rule.
func _offerable(entry: Dictionary) -> bool:
	if bool(entry.get("equipped", false)) or not bool(entry.get("known", true)):
		return false
	return not (entry.get("claimable_slots", []) as Array).is_empty()


# --- Reporting --------------------------------------------------------------


func _row_summaries() -> Array:
	var out: Array = []
	for row in _rows:
		var view: Dictionary = row.call(&"summary")
		if not view.is_empty():
			out.append(view)
	return out


func _ids_where(rows: Array, flag: String) -> Array:
	var out: Array = []
	for row in rows:
		if bool((row as Dictionary).get(flag, false)):
			out.append(String((row as Dictionary).get("id", "")))
	return out
