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
## ## The MARGIN line: what the sheet says, and what a copy may say instead
##
## ADR 0196/0204 make a copied manual a BAND around an authored figure rather than a
## different authored figure, and that band used to be drawn (`draw` rolled it) and
## published nowhere — a player was told `6.0` and had no way to learn that a copy
## might read `4.5`. `inspect` now publishes the two edges as `marginal_band`
## `{floor, ceiling}`, and this row prints them BESIDE the authored column so the
## two statements sit together: *this sheet says 6.0; a copy may read 4.5-7.5.*
##
## **The row does not compute the band, and it does not apply it.** Both numbers are
## the module's, arrived at through the one declaration in
## `TechniqueMarginalia.band_for`; multiplying the authored figure by an edge derived
## here would be a second reader of a roll rule, which is the defect this line closes
## (DEF-0302). The row also never says `1.0-1.0` for a copy that cannot vary: the
## module's `marginal_banded` says whether the edges bite at all, and a COMMON manual,
## an active manual and a capacity-only manual all read as the sheet, which is what
## they are.
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

## The study statements. Every `%d` is a module figure; this panel formats
## them and never produces one.
const UNKNOWN_TEXT := "Not learned"
const COST_TEXT := "Not learned - costs %d progress"
const FREE_TEXT := "Not learned - free to learn"
const GATE_MARK := " (gated)"
const SHORT_TEXT := "Short on %s: needs %d, held %d"
const GATE_TEXT := "Not yet: %s"

## The margin line. `%.2f` because the band is a MULTIPLIER on an authored figure,
## not a figure itself — it is printed to two decimals so `0.75` never reads as
## `0.8` next to a six-point option.
const BAND_TEXT := "This sheet says %s; a copy may read %s"
const NOTHING_AUTHORED := "no inscribed figure"

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
var _band: String = ""
var _note: String = ""
var _head_label: Label = null
var _meta_label: Label = null
var _mastery_label: Label = null
var _price_label: Label = null
var _band_label: Label = null
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
	_band = _band_text(_view)
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
		# The RANGE a copy may read, and whether it means anything for this row.
		# Published RELAYED, never derived here: a consumer compares these against
		# `marginal_band_figures` itself, so no screen had to work out either edge
		# (DEF-0302).
		#
		# Two units, because a player reads both and conflating them is the bug this
		# separates. `marginal_span` is the MULTIPLIER window the module declares for
		# this rarity — 0.75 and 1.25 — which is the RULE. `marginal_band` is the
		# PRICE window it works out on this manual's own values — 4.5 and 7.5 on a
		# sheet that says 6.0 — and is what `_band_text` prints beside the figure.
		# Reading the price window as if it were the multiplier is what made this
		# surface report `1.0 .. 1.0` for every manual while the numbers it returned
		# for the right key were plain correct.
		"marginal_band": band_view(),
		"marginal_span": _span_view(),
		"marginal_banded": bool(_view.get("marginal_banded", false)),
		"marginal_band_figures": band_figures(),
		"head": _head,
		"meta": _meta,
		"mastery_line": _mastery,
		"price_line": _price,
		"band_line": _band,
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
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_mastery_label = get_node_or_null("%MasteryLabel") as Label
	_price_label = get_node_or_null("%PriceLabel") as Label
	_band_label = get_node_or_null("%BandLabel") as Label
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
	if _band_label == null:
		return
	_band_label.text = _band
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


## The MARGIN line: the authored figure and the range a copy of it may read.
##
## ## Why it prints the module's FIGURES, not a multiplication of its own
##
## `marginal_band` is a pair of multipliers, but a player is owed the range in the
## SAME UNITS as the sheet beside it — "this sheet says 6.0; a copy may read
## 4.50-7.50" — and multiplying `6.0` by `0.75` in a PANEL would mean the panel
## computed a figure ADR 0196's rule owns, in `ui/`, from an edge it read two keys
## away. Two readers of one roll is the defect DEF-0302 exists to close. So the
## module publishes the per-option figures (`marginal_band_figures`) and this row
## only formats them.
##
## Empty — and the label cleared — for a row whose range cannot bite. That is the
## module's `marginal_banded` answer, not this panel's: a COMMON copy spans
## `1.0 .. 1.0`, an ACTIVE manual authors no options to vary, and a capacity-only
## manual is carried at its authored value. A line reading "1.00x - 1.00x" would
## promise a precision no author declared.
func _band_text(view: Dictionary) -> String:
	if not bool(view.get("marginal_banded", false)):
		return ""
	var figures := band_figures()
	if figures.is_empty():
		return ""
	return BAND_TEXT % [_sheet_text(figures), _edges_text(figures, band_view())]


## The sheet's own column, quoted from the module's figures rather than recomputed
## from `authored_effects` and the edges.
func _sheet_text(figures: Array) -> String:
	var parts: Array[String] = []
	for figure in figures:
		var entry: Dictionary = figure as Dictionary
		var label := String(entry.get("label", ""))
		var value := float(entry.get("authored", 0.0))
		parts.append("%s %.2f" % [label, value])
	return " ".join(parts)


## The range, in the sheet's units, with the multiplier pair beside it when it is not
## the identity — the two edges are the module's statement about copies of this
## manual rather than about this one option, and a hero buying a copy wants both.
func _edges_text(figures: Array, band: Dictionary) -> String:
	var parts: Array[String] = []
	for figure in figures:
		var entry: Dictionary = figure as Dictionary
		var low := float(entry.get("floor", 0.0))
		var high := float(entry.get("ceiling", 0.0))
		parts.append("%.2f-%.2f" % [low, high])
	var floor_edge := float(band["floor"])
	var ceiling_edge := float(band["ceiling"])
	if floor_edge == 1.0 and ceiling_edge == 1.0:
		return " ".join(parts)
	return "%s (x%.2f-x%.2f)" % [" ".join(parts), floor_edge, ceiling_edge]


## The module's per-option range, normalised to primitives so a `summary()` consumer
## never receives whatever dictionary shape the caller happened to hold.
func band_figures() -> Array:
	var out: Array = []
	var published: Variant = _view.get("marginal_band_figures", [])
	if not published is Array:
		return out
	for figure in published as Array:
		if not figure is Dictionary:
			continue
		var entry: Dictionary = figure as Dictionary
		var option_id := String(entry.get("option_id", ""))
		var label := String(entry.get("label", ""))
		var authored := float(entry.get("authored", 0.0))
		var low := float(entry.get("floor", 0.0))
		var high := float(entry.get("ceiling", 0.0))
		(
			out
			. append(
				{
					"option_id": option_id,
					"label": label,
					"authored": authored,
					"floor": low,
					"ceiling": high,
				}
			)
		)
	return out


## The module's two edges, normalised to primitives so a `summary()` consumer never
## receives whatever dictionary shape the caller happened to hold. `1.0 .. 1.0` when
## nothing was published, which `marginal_banded` then says is meaningless.
##
## Read from `marginal_band_figures` — the key the module ACTUALLY publishes. It
## previously read a `marginal_band` key nothing has ever written, so every row
## fell through to the `1.0 .. 1.0` default and the screen reported no band for
## any manual: the surface was built, wired, and inert, which is the DEF-0302 shape
## the read model was written to close. The widest figure wins, because a manual
## with several options shows the envelope a copy could land anywhere inside.
func band_view() -> Dictionary:
	var figures := band_figures()
	if figures.is_empty():
		return {"floor": 1.0, "ceiling": 1.0}
	# Seeded from the FIRST figure, not from the neutral `1.0 .. 1.0`. Folding a
	# floor of 4.5 into a seed of 1.0 with `minf` can never move it — 1.0 is below
	# every price a band can reach — so the window came back `1.0 .. 7.5`: a real
	# ceiling and a floor that was never the module's at all. The neutral default
	# belongs to the EMPTY case only, which is the branch above.
	var first: Dictionary = figures[0]
	var out := {
		"floor": float(first.get("floor", 1.0)),
		"ceiling": float(first.get("ceiling", 1.0)),
	}
	for index in range(1, figures.size()):
		var row: Dictionary = figures[index]
		out["floor"] = minf(float(out["floor"]), float(row.get("floor", 1.0)))
		out["ceiling"] = maxf(float(out["ceiling"]), float(row.get("ceiling", 1.0)))
	return out


## The MULTIPLIER window the module declares for this manual's rarity, relayed.
##
## `ui/` may not call `TechniqueMarginalia.band_for` itself — the band is the
## module's rule, and a panel that re-derived it would be a second reader of ADR
## 0204. The read model publishes it as `marginal_band`; this relays it under a
## name that says which unit it is, because the PRICE window is published beside it
## and reading one as the other is how this surface came to report `1.0 .. 1.0` for
## every manual.
func _span_view() -> Dictionary:
	var out := {"floor": 1.0, "ceiling": 1.0}
	var published: Variant = _view.get("marginal_band", {})
	if not published is Dictionary:
		return out
	var span: Dictionary = published as Dictionary
	out["floor"] = float(span.get("floor", 1.0))
	out["ceiling"] = float(span.get("ceiling", 1.0))
	return out


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
