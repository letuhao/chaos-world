class_name NationOfficeRow
extends PanelContainer

## One seat on a nation's board, as `NationApi.summary(actor)` publishes it.
##
## ## A vacancy is a ROW, and this row is what makes that legible
##
## ADR 0083's middle state is `"vacant": true`: the seat EXISTS and its value is
## absent. So `show_office({...})` with `vacant` renders a **visible** row with its
## own tone and the word `Vacant`, while `show_office({})` — a spare row in the pool
## that no authored seat occupies — renders nothing at all and `is_filled()` answers
## false.
##
## Those two are deliberately built to look nothing alike, because the entire
## succession design depends on a player being able to tell them apart: an unfilled
## authored seat is a fact about the world, a spare row is an artefact of the widget
## pool. Collapsing either into `0`, into `"-"`, or into a hidden row would destroy
## the design that made the vacancy legible in the first place.
##
## `summary()` is the testable surface. Every format this row shows is the row's
## own; a screen passes raw values and renders nothing itself.

## Stands in for a seat's holder. A word, never the id and never a dash: an empty
## `holder_id` is a value that is ABSENT, and "-" would read as an authored value.
const VACANT_TEXT := "Vacant"
const UNFILLED_TEXT := "Unfilled"
const UNKNOWN_TEXT := "Seat unnamed"
const HOLDER_PREFIX := "Held by"
const METHOD_UNKNOWN := "succession unwritten"

var _view: Dictionary = {}
var _head: String = ""
var _holder: String = ""
var _method: String = ""
var _meta: String = ""
var _head_label: Label = null
var _holder_label: Label = null
var _method_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one seat as the facade publishes it:
## `{office_id, display_name, succession_method, capacity, vacant, holder_id, powers}`.
##
## An EMPTY dictionary is ADR 0083's FIRST state — this seat does not exist — so the
## row clears itself and hides. That is the whole difference between a spare pool row
## and a vacant office, and it is why the two are not the same call.
func show_office(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_holder = ""
		_method = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var vacant := bool(_view.get("vacant", false))
	var authored_name := String(_view.get("display_name", ""))
	_head = authored_name if authored_name != "" else String(_view.get("office_id", ""))
	if _head == "":
		_head = UNKNOWN_TEXT
	# The one line that must never be ambiguous: a seat with no holder says so in
	# words. It is not an empty string, a zero, or a dash.
	_holder = VACANT_TEXT if vacant else "%s %s" % [HOLDER_PREFIX, holder_id()]
	_method = String(_view.get("succession_method", ""))
	_method = METHOD_UNKNOWN if _method == "" else _method
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_office({})


## Everything the row shows, primitives only. `{}` when the seat does not exist —
## never a shaped row with empty fields, which is what would make a spare pool row
## and a vacant seat read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"office_id": office_id(),
		"display_name": String(_view.get("display_name", "")),
		# ADR 0083's middle state, carried into the testable surface explicitly so
		# a test reads the seat's existence rather than inferring it from a blank.
		"vacant": bool(_view.get("vacant", false)),
		"holder_id": holder_id(),
		"held": not bool(_view.get("vacant", false)) and holder_id() != "",
		"capacity": int(_view.get("capacity", 0)),
		"succession_method": _method,
		"powers": _string_list(_view.get("powers", [])),
		"head": _head,
		"holder_line": _holder,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"holder_tone": String(_holder_tone()),
		"card_tone": String(_card_tone()),
		"focus_target": "NationOfficeRow",
	}


## Whether this seat EXISTS. A vacant seat answers true and renders; a spare row in
## the pool answers false and does not. The distinction is the whole point of the
## row, so it is a named predicate rather than something a caller infers.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether this is an authored seat nobody holds — the state `summary()` renders as
## `vacant: true` and never as a zero.
func is_vacant() -> bool:
	return is_filled() and bool(_view.get("vacant", false))


func office_id() -> String:
	return String(_view.get("office_id", ""))


## The id of whoever holds the seat, or `""` when nobody does. The empty string is
## the ABSENT VALUE; `is_vacant()` is what tells a caller it is absent rather than
## unread.
func holder_id() -> String:
	return String(_view.get("holder_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_holder_label = get_node_or_null("%HolderLabel") as Label
	_method_label = get_node_or_null("%MethodLabel") as Label
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
	_holder_label.text = _holder
	_holder_label.theme_type_variation = _holder_tone()
	_method_label.text = _method
	_meta_label.text = _meta


## The card a filled seat paints itself with, and the card a VACANT one paints
## itself with. They are different variations on purpose: a board where every
## unfilled seat looks like a filled one has thrown away the succession design.
func _card_tone() -> StringName:
	return &"VacantSeatCard" if is_vacant() else &"FilledSeatCard"


## A vacant seat's name is still its name — the seat exists — but it is printed in
## the vacancy tone so the eye finds the gap without reading the line under it.
func _head_tone() -> StringName:
	return &"VacantSeatLabel" if is_vacant() else &"SeatLabel"


## "Vacant" is the loudest thing on the board. A filled seat names its holder in the
## quiet tone, because a holder is the expected state and needs no announcement.
func _holder_tone() -> StringName:
	return &"VacantSeatLabel" if is_vacant() else &"SeatHolderLabel"


## "vacant · 1 seat · filled by trial". Every number and every word here belongs to
## the row; the screen passes raw values and formats nothing.
func _meta_text() -> String:
	if is_vacant():
		return "vacant · %d seat(s) · to be filled by %s" % [int(_view.get("capacity", 0)), _method]
	return "%d seat(s) · filled by %s" % [int(_view.get("capacity", 0)), _method]


func _string_list(values: Variant) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for value in values as Array:
		out.append(String(value))
	return out
