class_name PortraitPickerRow
extends PanelContainer

## One offered face: the name the catalogue authored, and a button that is a
## REQUEST for that face — never a grant.
##
## ## Why this row holds a button at all, when the codex row holds none
##
## `DestinyBranchRow` is a report: a held destiny is something the player earned
## and cannot change, so it publishes no verb. A face at creation is the opposite —
## it is a question with no answer yet, so the row publishes exactly one press and
## the screen hands the id to `PortraitResolver.choose`. One press, one id, no
## second path.
##
## The row owns every string it shows, so the picker above formats nothing and a
## test asserts this row's `summary()`, not pixels.

## The press. Carries the portrait id only. The screen decides what to do with it.
signal chosen(portrait_id: StringName)

const EMPTY_TEXT := "LOC_UI_PANELS_DFC6C5C708"
const TAKE_TEXT := "LOC_UI_PANELS_D47965AB1E"
const WORN_TEXT := "LOC_UI_PANELS_CAFE5884FE"
const NO_NAME := "LOC_UI_PANELS_9CA8E487DB"

var _view: Dictionary = {}
var _portrait_id: StringName = &""
var _head: String = ""
var _meta: String = ""
var _head_label: Label = null
var _meta_label: Label = null
var _take_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one offered face as `PortraitPicker` publishes it: `{portrait_id,
## race_id, display_name, form, honoured, selected}`. An empty dictionary clears
## the row, which is what a spare row in the bounded pool shows.
func show_face(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		clear()
		return
	_view = view.duplicate(true)
	_portrait_id = StringName(_view.get("portrait_id", ""))
	_head = _head_text()
	_meta = _meta_text()
	_render()


func clear() -> void:
	_view = {}
	_portrait_id = &""
	_head = ""
	_meta = ""
	_render()


## Everything this row shows, primitives only. `{}` when the row carries nothing,
## which is how a test tells an offered face from a spare pooled row.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"portrait_id": String(_portrait_id),
		"race_id": String(_view.get("race_id", "")),
		"display_name": String(_view.get("display_name", "")),
		"form": String(_view.get("form", "")),
		"honoured": bool(_view.get("honoured", false)),
		"selected": bool(_view.get("selected", false)),
		"can_take": can_take(),
		"head": _head,
		"meta": _meta,
		"button_text": _button_text(),
		"focus_target": "PortraitPickerRow",
	}


## The face this row offers, or `""` when the row is empty.
func portrait_id() -> StringName:
	return _portrait_id


## Whether the press is a live control. A pooled spare row is not, so a test can
## tell "offered" from "present".
func can_take() -> bool:
	return not _view.is_empty() and not _portrait_id.is_empty()


## Give the keyboard a landing spot. Recorded by the screen rather than grabbed
## here: this row may not be inside a viewport yet, and `AGENTS.md` forbids
## `grab_focus()` in `_ready()`.
func focus_initial() -> void:
	_bind_nodes()
	if _take_button != null and _take_button.is_inside_tree() and can_take():
		_take_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolved on first use rather than in `@onready`: the headless runner drives
## this row before a scene tree exists. Idempotent, and the connect is guarded so
## a re-resolved button cannot stack a second handler per press (AGENTS.md).
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%FaceHeadLabel") as Label
	_meta_label = get_node_or_null("%FaceMetaLabel") as Label
	_take_button = get_node_or_null("%TakeFaceButton") as Button
	if _take_button != null and not _take_button.pressed.is_connected(_on_pressed):
		_take_button.pressed.connect(_on_pressed)


func _render() -> void:
	if _head_label == null:
		return
	visible = not _view.is_empty()
	if not visible:
		return
	_head_label.text = L.t(_head)
	_meta_label.text = L.t(_meta)
	if _take_button == null:
		return
	_take_button.disabled = not can_take()
	_take_button.text = L.t(_button_text())
	# The plain `Button` variation for an offered face and `PrimaryButton` for the
	# chosen one: the selected row is the one action this panel is about, and the
	# theme's own base button needs no new variation invented for it.
	_take_button.theme_type_variation = (
		&"PrimaryButton" if bool(_view.get("selected", false)) else &"Button"
	)


## The authored name, or the id, or an admission that there is none — the three
## states a face can be in and none of them is a silent blank.
func _head_text() -> String:
	var authored := String(_view.get("display_name", ""))
	if not authored.is_empty():
		return authored
	if _portrait_id.is_empty():
		return L.t(NO_NAME)
	return String(_portrait_id)


## The face's body plan, in the vocabulary the row was given. No number is
## formatted here and none arrives: the picker publishes raw values and this row
## owns what a player reads.
func _meta_text() -> String:
	var form := String(_view.get("form", ""))
	var race := String(_view.get("race_id", ""))
	var parts: Array = []
	if not race.is_empty():
		parts.append("body %s" % race)
	if not form.is_empty():
		parts.append("form %s" % form)
	if parts.is_empty():
		return L.t(EMPTY_TEXT)
	return "  ".join(parts)


func _button_text() -> String:
	if not can_take():
		return L.t(EMPTY_TEXT)
	return WORN_TEXT if bool(_view.get("selected", false)) else TAKE_TEXT


## A REQUEST. The row names the face it was built with and the screen asks the
## resolver, so the only place a chosen face is written is the verb that owns it.
func _on_pressed() -> void:
	if not can_take():
		return
	chosen.emit(_portrait_id)
