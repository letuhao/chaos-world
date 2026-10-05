class_name PortraitPicker
extends PanelContainer

## The faces a hero MAY wear, offered at creation, and which one they took.
##
## ## What this is, and what it is not
##
## **An offer, never a gate.** Nothing here can refuse a creation: with no
## catalogue, no options or a failed lookup this panel publishes an empty
## `options` list and creation carries on resolving race-then-placeholder exactly
## as it did before this control existed (ADR 0257 §5).
##
## **A face decides nothing.** It changes no gate, no arrival, no stat and no
## fate — which is what keeps this off ADR 0065's forbidden fate picker. The row
## owns no verb that grants; it reports an id and the screen hands it to
## `PortraitResolver.choose`, the single place a chosen face is ever written.
##
## ## Every option is one `resolve` would HONOUR
##
## A list built from the catalogue by race alone would offer the shadowed
## variants BL-0883 measured — two entries that render identically, so choosing
## one is a choice that is not one. So an option is admitted only when asking the
## resolver for exactly that portrait answers with that same portrait: the base
## face for the race, or a variant `for_variant` genuinely reaches. A face the
## resolver would then override is never offered (ADR 0257 §3).
##
## ## The bound, and why it is `RowBudget` and not a local number
##
## `RowBudget.cap()` — ONE shared number, because six independently-chosen caps
## would drift and the one that matters is the smallest. The catalogue is DATA:
## `_portrait_options` walks it, and a walk over a data-derived row count with one
## live `Control` parented per row is exactly the shape behind the recorded 67 GB
## / 105 GB commit incident (INC-0002) — a grow loop bounded by a snapshot it is
## itself growing passes every output ceiling, because it allocates in silence.
## `shown`/`total` are published so a truncated list SAYS it is showing N of M
## rather than pretending the catalogue ended.
##
## Contract: `summary()` is primitives only; the row owns every format, so this
## panel formats no number and this screen formats nothing.

## The press. Carries a portrait id ONLY, and `""` means "take no face", which is
## a legal answer rather than a reset.
signal chosen(portrait_id: StringName)

const ROW_SCENE := "res://src/ui/panels/portrait_picker_row.tscn"
const HEADER := "Choose a face, or arrive as you are."
const OPTIONAL_NOTE := "Optional. Leave it and you are given your body's own face."

## One face, as primitives, in the shape `resolve` publishes. Every option has
## `honoured == true` by construction (see [method _is_honoured]), so a caller can
## read the field rather than re-deriving the rule.
const OPTION_FIELDS := ["portrait_id", "race_id", "display_name", "form", "honoured"]

var _race_id: StringName = &""
var _selected: StringName = &""
var _options: Array[Dictionary] = []
var _total: int = 0
var _header_label: Label = null
var _note_label: Label = null
var _row_box: VBoxContainer = null
var _rows: Array = []
var _bound_nodes: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Offer the faces `race_id` may wear. Empty is a legal answer, not a failure: an
## empty catalogue or an unknown body publishes zero options and the hero resolves
## exactly as it did before this control existed.
func show_race(race_id: StringName, selected: StringName = &"") -> void:
	_bind_nodes()
	_race_id = race_id
	_selected = selected
	_options = _portrait_options(race_id)
	_total = _options.size()
	_rows = _rows_in()
	_render()


## Every offered face, primitives only. The published contract a test asserts
## against: sorted ids, all honoured, and never more than `RowBudget.MAX_ROWS`.
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _options:
		var view: Dictionary = {}
		for field in OPTION_FIELDS:
			view[field] = entry.get(field, "")
		view["honoured"] = bool(entry.get("honoured", false))
		out.append(view)
	return out


## The face this hero will be created with, or `""` — which is the answer, not an
## absence. A hero with `""` resolves race-then-placeholder (ADR 0131).
func selected_id() -> StringName:
	return _selected


## Whether this panel OFFERS `portrait_id`. The gate a caller asks before
## recording a choice, kept separate from [method take] so validation never
## mutates and never emits.
func offers(portrait_id: StringName) -> bool:
	if portrait_id.is_empty():
		return true
	for entry in _options:
		if StringName(entry.get("portrait_id", "")) == portrait_id:
			return true
	return false


## Record `portrait_id` as this panel's selection, or nothing when it is `""`.
## Refuses an id this panel never offered rather than storing it: the screen must
## not be able to write a face the catalogue cannot explain, which is the same
## contract `choose` enforces itself.
##
## ## Why this does NOT emit `chosen`
##
## **It is the callee, not the caller.** The row emits `chosen`, the screen
## receives it and calls [method take] — so emitting here re-entered the screen's
## handler and recursed until the stack overflowed. The signal belongs to the
## event that caused the selection (a press); this method is what that event
## leads to. A method that both announces and handles its own announcement is a
## cycle the call graph cannot show, and it is why this is two verbs.
func take(portrait_id: StringName) -> bool:
	_bind_nodes()
	if not offers(portrait_id):
		return false
	_selected = portrait_id
	_render()
	return true


func summary() -> Dictionary:
	_bind_nodes()
	return {
		"race_id": String(_race_id),
		"selected_id": String(_selected),
		"has_options": not _options.is_empty(),
		"option_count": _options.size(),
		"total_count": _total,
		"shown_of_total": _options.size(),
		"truncated": RowBudget.truncated(_options.size(), _total),
		"header": HEADER,
		"note": OPTIONAL_NOTE,
		"options": options(),
		"option_ids": _option_ids(),
	}


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _bound_nodes:
		return
	_header_label = get_node_or_null("%PickerHeader") as Label
	_note_label = get_node_or_null("%PickerNote") as Label
	_row_box = get_node_or_null("%Faces") as VBoxContainer
	_bound_nodes = _header_label != null and _row_box != null
	if not _bound_nodes:
		return
	_rows = _rows_in()


func _render() -> void:
	if _header_label == null:
		return
	_header_label.text = HEADER
	_note_label.text = OPTIONAL_NOTE
	# A fixed pass over the POOL, and the pool is already bounded by `RowBudget` in
	# `_rows_in`. Every spare row is fed `{}` rather than skipped, so a stale face
	# from a previous race cannot stay on screen.
	for index in _rows.size():
		var row := _rows[index] as Control
		if row == null:
			continue
		var view: Dictionary = {}
		if index < _options.size():
			view = (_options[index] as Dictionary).duplicate(true)
			view["selected"] = StringName(view.get("portrait_id", "")) == _selected
		row.call(&"show_face", view)


## The rows, grown to the bound ONCE and never re-grown — a pool, not a rebuild.
##
## LOOP GUARD: the count is taken from `_total` and clamped by [method RowBudget.cap]
## BEFORE `range`, and the loop appends one row per index over a fixed range, so it
## terminates on its own arithmetic and the body grows only the array of already
## built rows. Nothing here re-reads `_rows.size()` as its own bound.
func _rows_in() -> Array:
	if _row_box == null:
		return []
	var out: Array = []
	for child in _row_box.get_children():
		if child is Control:
			out.append(child)
	var target: int = maxi(out.size(), RowBudget.cap(_total))
	for index in range(out.size(), target):
		var grown := (load(ROW_SCENE) as PackedScene).instantiate() as Control
		grown.name = "Face%d" % index
		_row_box.add_child(grown)
		out.append(grown)
	# ## The press route, and why it is connect-then-take rather than connect-to-state
	# ##
	# A row emits its own id; this panel records it and re-emits upward. Recording
	# it HERE is what marks the row Worn, and re-emitting is what the screen
	# listens for — so the screen's `act_choose_face` receives an announcement that
	# has already been applied, and its own call to `take` only re-renders. The
	# guard is `is_connected` because these rows are pooled and re-bound, and an
	# unguarded connect fires the handler once per press per bind (AGENTS.md).
	for row in out:
		var signal_ref: Signal = (row as Node).get(&"chosen")
		if not signal_ref.is_connected(_on_row_chosen):
			signal_ref.connect(_on_row_chosen)
	return out


## A row announced a face. Record it here, then pass it on. The one hop, in that
## order: the screen must never be the only place that knows which row is worn.
func _on_row_chosen(portrait_id: StringName) -> void:
	if not take(portrait_id):
		return
	chosen.emit(portrait_id)


# --- The catalogue walk -----------------------------------------------------


## The faces `race_id` may wear, in SORTED ID ORDER, so two runs offer the same
## list in the same sequence.
##
## ## What is excluded, and why each exclusion is a correctness rule
##
## - **The placeholder.** It is the face every actor gets before any art exists
##   (ADR 0131), not a face a player chooses, and offering it would put "no
##   choice" in the list as if it were one.
## - **A body plan that does not match.** A variant for the tidecaller is not a
##   face for the emberblood (ADR 0177).
## - **A face `resolve` would override.** [method _is_honoured] is the whole filter
##   and it is asked of the resolver rather than re-derived.
##
## ## The bound is taken HERE, before the walk appends anything
##
## `RowBudget.cap(_total)` is the shared number the whole tree clamps through. It
## is computed from the snapshot and held for the whole loop, so the loop cannot
## grow the thing it is bounded by (INC-0002): the collection was finished before
## this loop started, and nothing below adds to it.
func _portrait_options(race_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if race_id.is_empty():
		return out
	var catalog := PortraitCatalog.instance()
	for portrait_id in catalog.ids():
		var def := catalog.portrait_definition(portrait_id)
		if def == null or def.is_placeholder():
			continue
		if def.race_id != race_id:
			continue
		var honoured := _is_honoured(def, race_id)
		if not honoured:
			continue
		(
			out
			. append(
				{
					"portrait_id": String(def.id),
					"race_id": String(def.race_id),
					"display_name": def.display_name,
					"form": def.trait_value("form"),
					"honoured": true,
					"variant": _declaring_variant(def),
				}
			)
		)
	return out


## Whether asking the resolver to render `def` would render `def` back.
##
## ## Why this asks the resolver instead of re-deriving `for_variant`
##
## The rule "first in sorted id order wins" (ADR 0177) lives in
## `PortraitCatalog.for_variant`, and a second copy of it in `ui/` is a rule that
## drifts from the one that decides. So the question is put to the catalogue as a
## question: if this def declares a variant, is the one the catalogue REACHES for
## that variant this same def? If it is not, some other portrait owns it, and
## offering this one would hand the player two entries that render identically —
## the shadowing BL-0883 measured, which a picker makes visible.
##
## A def with no variant is the base face for its race and is always honoured: it
## is what `resolve` answers with before any variant is requested.
func _is_honoured(def: PortraitDef, race_id: StringName) -> bool:
	var variant := _declaring_variant(def)
	if variant.is_empty():
		return true
	var reached := PortraitCatalog.instance().for_variant(race_id, variant)
	return reached != null and reached.id == def.id


## The single `axis:value` trait this def declares as a SELECTABLE variant, or
## `""`.
##
## Only the axes ADR 0177 named are asked about. `palette:` and `class:` are not
## variants — two portraits sharing `palette:neutral` is a style, not a collision —
## and matching on the AXIS alone would make every `form:` portrait a candidate for
## every `form:` request, which is how a def stands in for a variant it was never
## drawn as (the reason `declares_variant` matches WHOLE).
func _declaring_variant(def: PortraitDef) -> String:
	for axis in ["action", "stage", "role", "beat", "place", "form"]:
		var found := def.trait_value(axis)
		if not found.is_empty():
			return "%s:%s" % [axis, found]
	return ""


func _option_ids() -> Array:
	var out: Array = []
	for entry in _options:
		out.append(String(entry.get("portrait_id", "")))
	return out
