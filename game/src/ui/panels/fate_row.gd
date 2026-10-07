class_name FateRow
extends PanelContainer

## One entry in the fate codex: an earned fate with its name, description and
## category, or one still locked.
##
## A fate authored with `visibility == &"hidden"` is listed but **unnamed**. The
## facade publishes no `display_name` for such an entry and this row prints only
## the teaser it was handed — never the id standing in for the name, which would
## be the same spoiler in different ink. A `&"teaser"` fate never reaches the
## screen at all; the facade filters it before the codex is built.
##
## The row owns every format it shows — the modifier count, the "not yet earned"
## wording, the heading that separates locked entries from earned ones — so a
## screen never renders a number. `summary()` is the testable surface.

## Stands in for a hidden fate's name. A marker, never the name and never the id.
var UNNAMED_HEAD := L.t("LOC_UI_PANELS_9B115C99B1")
var EARNED_TEXT := L.t("LOC_UI_PANELS_257F305B04")
var LOCKED_META := L.t("LOC_UI_PANELS_2EAAB6910F")
var SECTION_PREFIX := L.t("LOC_UI_PANELS_A798882F1C")
var SECTION_TAIL := L.t("LOC_UI_PANELS_63CFEB1E46")
## The row doubles as the heading between the earned and the locked entries, so
## the count it shows belongs to the row rather than to the screen.
const CATEGORY_UNKNOWN := "uncategorised"

var _view: Dictionary = {}
var _head: String = ""
var _description: String = ""
var _meta: String = ""
var _section: bool = false
var _locked_count: int = 0
var _head_label: Label = null
var _description_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one fate as `DestinyApi.summary(actor)` publishes it:
## `{id, held, display_name, description, teaser, category, modifier_count, ...}`.
## An empty dictionary clears the row, which is what a spare row in the pool
## shows.
func show_fate(view: Dictionary) -> void:
	_bind_nodes()
	_section = false
	_locked_count = 0
	if view.is_empty():
		_view = {}
		_head = ""
		_description = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var held := bool(_view.get("held", false))
	var authored_name := String(_view.get("display_name", ""))
	if held:
		_head = authored_name if authored_name != "" else String(_view.get("id", ""))
		_description = String(_view.get("description", ""))
		_meta = _earned_meta()
	elif authored_name == "":
		# Hidden and unearned: the teaser is the whole entry, by design.
		_head = UNNAMED_HEAD
		_description = _teaser()
		_meta = LOCKED_META
	else:
		_head = authored_name
		_description = String(_view.get("description", ""))
		_meta = _locked_meta()
	_render()


## Render this row as the heading between the earned fates and the locked ones.
## `locked_count` arrives raw; the wording belongs to the row.
func show_section(locked_count: int) -> void:
	_bind_nodes()
	_view = {}
	_section = true
	_locked_count = maxi(0, locked_count)
	_head = "%s — %d" % [SECTION_PREFIX, _locked_count]
	_description = ""
	_meta = SECTION_TAIL
	_render()


func clear() -> void:
	show_fate({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"entry": not _section,
		"section": _section,
		"id": fate_id(),
		"held": bool(_view.get("held", false)),
		"named": _named(),
		"category": String(_view.get("category", "")),
		"tier": int(_view.get("tier", 0)),
		"modifier_count": int(_view.get("modifier_count", 0)),
		"tags": _string_list(_view.get("tags", [])),
		"locked_count": _locked_count,
		"head": _head,
		"description": _description,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"focus_target": "FateRow",
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return _section or not _view.is_empty()


## Whether this row is the earned/locked heading rather than a fate.
func is_section() -> bool:
	return _section


func fate_id() -> String:
	return String(_view.get("id", ""))


## The id every row reports to the screen, whatever it is showing. A heading is
## never one, so it reports "".
func row_id() -> String:
	return "" if _section else fate_id()


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
	_description_label = get_node_or_null("%DescriptionLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_variation()
	if not visible:
		return
	_head_label.text = L.t(_head)
	_head_label.theme_type_variation = _head_tone()
	_description_label.text = L.t(_description)
	_description_label.visible = not _description.is_empty()
	_description_label.theme_type_variation = _body_tone()
	_meta_label.text = L.t(_meta)


## Whether the entry is allowed to show a name. A hidden fate is never one, so
## the id never leaks through this row.
func _named() -> bool:
	return _head != UNNAMED_HEAD and String(_view.get("display_name", "")) != ""


## The card the row paints itself with. Earned, locked and the heading are the
## three states a fate entry can be in, and the theme names each one.
func _card_variation() -> StringName:
	if _section:
		return &"LockedCard"
	return &"EarnedCard" if bool(_view.get("held", false)) else &"LockedCard"


func _head_tone() -> StringName:
	if _section:
		return &"LockedLabel"
	if bool(_view.get("held", false)):
		return &"EarnedLabel"
	return &"LockedLabel" if not _named() else &"FateNameLabel"


func _body_tone() -> StringName:
	return &"EffectLabel" if bool(_view.get("held", false)) else &"LockedLabel"


## "Earned · oath · 2 modifiers". Every number here is the row's to render.
func _earned_meta() -> String:
	return (
		"%s · %s · %d modifiers"
		% [
			EARNED_TEXT,
			_category(),
			int(_view.get("modifier_count", 0)),
		]
	)


func _locked_meta() -> String:
	return "Locked · %s" % _category()


func _category() -> String:
	var category := String(_view.get("category", ""))
	return category if category != "" else CATEGORY_UNKNOWN


func _teaser() -> String:
	var teaser := String(_view.get("teaser", ""))
	return teaser if teaser != "" else String(_view.get("description", ""))


func _string_list(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
