class_name TechniqueEntryRow
extends PanelContainer

## One learned technique in the codex: its grade, its paths, active or passive,
## the mastery rung it has reached, and what learning it would cost.
##
## Read-only. Learning is paid for out of progress the hero owns elsewhere and
## the codex never offers to do it, so this row publishes no action — the screen
## that owns it is the read-only half of ADR 0053's two screens.
##
## The row owns every format it shows — the `d2/5` rung, the learn price, the
## "known"/"not learned" wording — so a screen never renders a number.
##
## Contract: `summary()` is the testable surface. `{}` when the row carries nothing.

## Stands in for a technique whose name the catalog could not resolve. A marker,
## never the raw id.
const UNNAMED_HEAD := "Unnamed technique"
const EMPTY_TEXT := "Empty"
const SUSPENDED_TEXT := "SUSPENDED"
const MASTERY_TEXT := "Mastery"
const KNOWN_TEXT := "Known"
const UNKNOWN_TEXT := "Not learned"

var _view: Dictionary = {}
var _head: String = ""
var _meta: String = ""
var _mastery: String = ""
var _price: String = ""
var _head_label: Label = null
var _meta_label: Label = null
var _mastery_label: Label = null
var _price_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one technique as the technique facade publishes it: the codex row
## `TechniquesApi.summary` lists, extended with the two fields only
## `TechniquesApi.inspect` answers — the mastery ladder's reach and what the
## technique would cost to learn. An empty dictionary clears the row, which is
## what a spare row in the pool shows.
func show_entry(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_head = _head_text(_view)
	_meta = _meta_text(_view)
	_mastery = _mastery_text(_view)
	_price = _price_text(_view)
	_render()


func clear() -> void:
	show_entry({})


## Everything the row shows, primitives only. `{}` when it carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	var known := bool(_view.get("known", false))
	return {
		"id": String(_view.get("id", "")),
		"display_name": _head if _named() else "",
		"grade": String(_view.get("grade", "")),
		"path": String(_view.get("path", "")),
		"paths": _string_list(_view.get("paths", [])),
		"active": bool(_view.get("active", false)),
		"known": known,
		"equipped": bool(_view.get("equipped", false)),
		"suspended": bool(_view.get("suspended", false)),
		"rung": int(_view.get("rung", 0)),
		"rung_count": int(_view.get("rung_count", 0)),
		"learn_price": float(_view.get("learn_price", 0.0)),
		"can_learn": bool(_view.get("can_learn", false)),
		"learn_blocked_by": _string_list(_view.get("learn_unmet", [])),
		"head": _head,
		"meta": _meta,
		"mastery_line": _mastery,
		"price_line": _price,
		"empty": false,
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


func entry_id() -> String:
	return String(_view.get("id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first,
## because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this row before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_mastery_label = get_node_or_null("%MasteryLabel") as Label
	_price_label = get_node_or_null("%PriceLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_variation()
	_meta_label.text = _meta
	_meta_label.theme_type_variation = &"EffectLabel" if known_entry() else &"MetaLabel"
	_mastery_label.text = _mastery
	_price_label.text = _price


## A technique the catalog could not name. Never the raw id: an unresolvable id is
## a content gap, and printing it would read as a name.
func _head_text(view: Dictionary) -> String:
	var name := String(view.get("display_name", ""))
	if name.is_empty():
		return UNNAMED_HEAD if view.has("id") else EMPTY_TEXT
	return name


func _named() -> bool:
	return String(_view.get("display_name", "")) != ""


## `qi · mortal · passive · equipped`. The facts a codex row is scanned for,
## with no number in it — the rung and the price have lines of their own.
func _meta_text(view: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_path_text(view))
	var grade := String(view.get("grade", ""))
	if not grade.is_empty():
		parts.append(grade)
	parts.append("active" if bool(view.get("active", false)) else "passive")
	if bool(view.get("equipped", false)):
		parts.append("equipped")
	if bool(view.get("suspended", false)):
		parts.append(SUSPENDED_TEXT)
	return " · ".join(parts)


## `Mastery d2/5`, or `Mastery d2` when the technique has no authored ladder.
func _mastery_text(view: Dictionary) -> String:
	var rung := int(view.get("rung", 0))
	var reach := int(view.get("rung_count", 0))
	if reach <= 0:
		return "%s d%d" % [MASTERY_TEXT, rung]
	return "%s d%d/%d" % [MASTERY_TEXT, rung, reach]


## `Known` for a learned technique; `Not learned — 120` for one the hero has not
## paid for, because "what it would cost to learn" is the question the codex
## exists to answer for both.
func _price_text(view: Dictionary) -> String:
	if known_entry():
		return KNOWN_TEXT
	var price := float(view.get("learn_price", 0.0))
	var gate := "" if bool(view.get("can_learn", false)) else " (gated)"
	return "%s - %d%s" % [UNKNOWN_TEXT, int(round(price)), gate]


## The path or paths a DUAL technique occupies. `paths` is the read model's
## normalised list; `path` is the raw authored field for a path-exclusive row.
func _path_text(view: Dictionary) -> String:
	var listed: Array = view.get("paths", [])
	if not listed.is_empty():
		return " + ".join(_string_list(listed))
	var authored := String(view.get("path", ""))
	return authored if authored != "" else "unpathed"


func _head_variation() -> StringName:
	if bool(_view.get("suspended", false)):
		return &"WarnLabel"
	return &"SectionTitle" if _named() else &"MetaLabel"


func known_entry() -> bool:
	return bool(_view.get("known", false))


func _string_list(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
