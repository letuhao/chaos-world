class_name TechniqueEntryRow
extends PanelContainer

## One technique in the codex: its grade, its paths, active or passive, the mastery
## rung it has reached, and what learning it would cost.
##
## Read-only. Learning is paid for out of progress the hero owns elsewhere and
## the codex never offers to do it, so this row publishes no action — the screen
## that owns it is the read-only half of ADR 0053's two screens.
##
## ## What the study line says, and what it refuses to say
##
## A price a hero cannot compare against their own progress is half a feature, so
## the price is never printed alone. The row renders the module's three answers
## together, and each is printed ONLY when the module published it:
##
##   - **the gate** (`learn_unmet`) — what must be true first;
##   - **the price** (`learn_price`) — what the study charges;
##   - **the shortfall** (`learn_short`) — which path, what was owed and what was
##     held, in the module's own `{resource, required, current}` shape.
##
## **The row decides none of them.** `learn_price` arrives computed (ADR 0160,
## `LEARN_BASE * LEARN_STEP^ordinal * grade`), the gate arrives as the module's
## labels, and the shortfall arrives as the module's `short` list. A row that
## re-derived "can this actor pay" would own ADR 0160's payer rule, which is the
## module's — the same rule `anchor_construction_row.gd` obeys by taking `missing`
## from `AnchorApi.summary` rather than counting the bag.
##
## ## A KNOWN technique costs nothing
##
## `inspect().learn_price` is the price of a DUPLICATE manual, so it is published
## for learned techniques too. The row publishes `0.0` for a known entry: a consumer
## reading `summary()` must never conclude that holding a technique costs money
## (DEF-0244).
##
## The row owns every format it shows — the `d2/5` rung, the price, the shortfall,
## the "known"/"not learned" wording — so a screen never renders a number.
##
## Contract: `summary()` is the testable surface. `{}` when the row carries nothing.

## Stands in for a technique whose name the catalog could not resolve. A marker,
## never the raw id.
const UNNAMED_HEAD := "Unnamed technique"
const EMPTY_TEXT := "Empty"
const SUSPENDED_TEXT := "SUSPENDED"
const MASTERY_TEXT := "Mastery"
const KNOWN_TEXT := "Known"

## The three study statements. Every `%d` is a module figure; this panel formats
## them and never produces one.
const UNKNOWN_TEXT := "Not learned"
const COST_TEXT := "Not learned - costs %d progress"
const FREE_TEXT := "Not learned - free to learn"
const GATE_MARK := " (gated)"
const SHORT_TEXT := "Short on %s: needs %d, held %d"
const GATE_TEXT := "Not yet: %s"

## The path ids a shortfall is reported against, in a hero's words rather than the
## module's. `qi_cultivation` is machine vocabulary; "the qi path" is not, and a
## shortfall a hero cannot name is a shortfall they cannot act on. Same mapping
## `technique_slot_row.gd` uses for its pools.
const POOL_TEXT := {
	"qi_cultivation": "the qi path",
	"body_cultivation": "the body path",
	"mind_cultivation": "the mind path",
	"universal": "the universal pool",
}

var _view: Dictionary = {}
var _head: String = ""
var _meta: String = ""
var _mastery: String = ""
var _price: String = ""
var _note: String = ""
var _head_label: Label = null
var _meta_label: Label = null
var _mastery_label: Label = null
var _price_label: Label = null
var _note_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one technique as the technique facade publishes it: the codex row
## `TechniquesApi.summary` lists, extended with the fields only
## `TechniquesApi.inspect` answers — the mastery ladder's reach, what the technique
## would cost to learn, and what stands between this actor and paying it. An empty
## dictionary clears the row, which is what a spare row in the pool shows.
func show_entry(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_head = _head_text(_view)
	_meta = _meta_text(_view)
	_mastery = _mastery_text(_view)
	_price = _price_text(_view)
	_note = _note_text(_view)
	_render()


func clear() -> void:
	show_entry({})


## Everything the row shows, primitives only. `{}` when it carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	var known := known_entry()
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
		# 0.0 for a KNOWN entry, deliberately: `inspect` prices the DUPLICATE
		# manual, and a row that published it for a technique the hero already holds
		# would tell a consumer the hero is charged for owning it (DEF-0244).
		"learn_price": 0.0 if known else float(_view.get("learn_price", 0.0)),
		"can_learn": bool(_view.get("can_learn", false)),
		# Relayed, never decided. False here means "the module has not said so",
		# which is why `note_line` below is the claim a player reads.
		"can_pay": false if known else bool(_view.get("can_pay", false)),
		"learn_blocked_by": _string_list(_view.get("learn_unmet", [])),
		"learn_short": short_list(),
		"head": _head,
		"meta": _meta,
		"mastery_line": _mastery,
		"price_line": _price,
		"note_line": _note,
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
	_note_label = get_node_or_null("%NoteLabel") as Label


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
	_price_label.theme_type_variation = &"MetaLabel" if known_entry() else &"EffectLabel"
	if _note_label == null:
		return
	_note_label.text = _note
	# A shortfall is the one line here that is a refusal, so it takes the row's only
	# alarming variation; a gate is a reason, and reads as one.
	_note_label.theme_type_variation = &"WarnLabel" if not short_list().is_empty() else &"MetaLabel"


# --- Formatting. Every string this row shows is built here -------------------


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


## The study price, or the fact that there is nothing left to pay.
##
## `Known` for a learned technique, because ADR 0160's price buys a DUPLICATE
## manual and printing it beside a technique the hero already holds would read as
## a debt. An unlearned one is quoted with the gate marker, because a hero who
## cannot pay AND cannot pass the gate is short for two different reasons and
## conflating them would hide one.
func _price_text(view: Dictionary) -> String:
	if known_entry():
		return KNOWN_TEXT
	var price := float(view.get("learn_price", 0.0))
	var quoted := FREE_TEXT if price <= 0.0 else COST_TEXT % int(round(price))
	if bool(view.get("can_learn", false)):
		return quoted
	return quoted + GATE_MARK


## The line that makes the price actionable: what the hero is short of, or why the
## study is not open yet.
##
## Printed only when the module published a reason. An unlearned technique with no
## shortfall and no gate prints nothing at all, which is the honest answer — a
## silence here means the module has not been asked, and the row will not invent a
## verdict the module never gave.
func _note_text(view: Dictionary) -> String:
	if known_entry():
		return ""
	var short := short_list()
	if not short.is_empty():
		return _short_text(short)
	var unmet := _string_list(view.get("learn_unmet", []))
	if unmet.is_empty():
		return ""
	return GATE_TEXT % ", ".join(unmet)


## What the hero is short of, in the module's own `{resource, required, current}`
## vocabulary: which path, what it owed and what it held.
func _short_text(short: Array) -> String:
	var parts: Array[String] = []
	for pool in short:
		var entry: Dictionary = pool as Dictionary
		(
			parts
			. append(
				(
					SHORT_TEXT
					% [
						_path_words(String(entry.get("resource", ""))),
						int(round(float(entry.get("required", 0.0)))),
						int(round(float(entry.get("current", 0.0)))),
					]
				)
			)
		)
	return "  ".join(parts)


## The module's shortfall list, as primitives. Every entry is normalised to three
## numbers and a name, so a `summary()` consumer never receives a module object.
func short_list() -> Array:
	var out: Array = []
	if known_entry():
		return out
	for pool in _view.get("learn_short", []) as Array:
		if not pool is Dictionary:
			continue
		var entry: Dictionary = pool as Dictionary
		(
			out
			. append(
				{
					"resource": String(entry.get("resource", "")),
					"required": float(entry.get("required", 0.0)),
					"current": float(entry.get("current", 0.0)),
				}
			)
		)
	return out


## The path or paths a DUAL technique occupies. `paths` is the read model's
## normalised list; `path` is the raw authored field for a path-exclusive row.
func _path_text(view: Dictionary) -> String:
	var listed: Array = view.get("paths", [])
	if not listed.is_empty():
		return " + ".join(_string_list(listed))
	var authored := String(view.get("path", ""))
	return authored if authored != "" else "unpathed"


## A path id as a hero would name it. An id this row does not know is printed
## verbatim rather than swallowed: a shortfall against a pool nobody can name is
## still a shortfall, and hiding it would be worse than showing the machine word.
func _path_words(path_id: String) -> String:
	return String(POOL_TEXT.get(path_id, path_id))


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
