class_name DestinyBranchRow
extends PanelContainer

## One held destiny, with the authored `bearing` line that is the whole point of
## earning one: the narrative payoff, shown in the author's voice rather than as
## a stat block.
##
## A destiny authored with `visibility == &"hidden"` is still a spoiler while it
## is locked, so an unheld entry is listed under a marker and carries its teaser
## instead of its name — the same rule `FateRow` follows for fates. A
## `&"teaser"` destiny never reaches the screen; the facade filters it.
##
## This row is a report, never a control. It holds no button, publishes no
## selection and offers nothing to press, because a destiny is earned and cannot
## be chosen or equipped (ADR 0065). `summary()` is the testable surface.

const UNNAMED_HEAD := "Unnamed"
const HELD_META := "Held for good."
const LOCKED_META := "Not yet earned."

var _view: Dictionary = {}
var _head: String = ""
var _description: String = ""
var _bearing: String = ""
var _meta: String = ""
var _head_label: Label = null
var _description_label: Label = null
var _bearing_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one destiny as `DestinyApi.summary(actor)` publishes it:
## `{id, held, group, display_name, description, bearing, grants_fate_count}`.
## An empty dictionary clears the row, which is what a spare row in the pool
## shows.
func show_destiny(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_description = ""
		_bearing = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var held := bool(_view.get("held", false))
	var authored_name := String(_view.get("display_name", ""))
	if held:
		_head = authored_name if authored_name != "" else String(_view.get("id", ""))
		_description = String(_view.get("description", ""))
		_bearing = String(_view.get("bearing", ""))
		_meta = _held_meta()
	elif authored_name == "":
		_head = UNNAMED_HEAD
		_description = _teaser()
		_bearing = ""
		_meta = LOCKED_META
	else:
		_head = authored_name
		_description = String(_view.get("description", ""))
		_bearing = ""
		_meta = "Locked · %s" % _group()
	_render()


func clear() -> void:
	show_destiny({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"id": destiny_id(),
		"held": bool(_view.get("held", false)),
		"named": _named(),
		"group": String(_view.get("group", "")),
		"tier": int(_view.get("tier", 0)),
		"grants_fate_count": int(_view.get("grants_fate_count", 0)),
		"has_bearing": _bearing != "",
		"head": _head,
		"description": _description,
		"bearing": _bearing,
		"bearing_line": _bearing,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"focus_target": "DestinyBranchRow",
	}


## The destiny this row shows, or "" when the row is empty.
func destiny_id() -> String:
	return String(_view.get("id", ""))


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## Give the keyboard and pad a landing spot. The target is recorded first,
## because a node outside a viewport has nothing to focus yet. Focusing a row is
## not selecting it: there is nothing here to choose.
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
	_bearing_label = get_node_or_null("%BearingLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_variation()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_tone()
	_description_label.text = _description
	_description_label.visible = not _description.is_empty()
	_description_label.theme_type_variation = (
		&"EffectLabel" if bool(_view.get("held", false)) else &"LockedLabel"
	)
	_bearing_label.text = _bearing
	_bearing_label.visible = _bearing != ""
	_meta_label.text = _meta


## Whether the entry is allowed to show a name. A hidden destiny is never one, so
## the id never leaks through this row.
func _named() -> bool:
	return _head != UNNAMED_HEAD and String(_view.get("display_name", "")) != ""


## The card the row paints itself with. A held destiny is the loudest thing in
## the codex; a locked one is the quietest.
func _card_variation() -> StringName:
	return &"DestinyCard" if bool(_view.get("held", false)) else &"LockedCard"


func _head_tone() -> StringName:
	if not bool(_view.get("held", false)):
		return &"LockedLabel" if not _named() else &"DestinyLockedLabel"
	return &"DestinyNameLabel"


## "Held for good · oath · carries 2 fate(s)". Every number here is the row's to
## render; the screen passes raw values.
func _held_meta() -> String:
	return (
		"%s · %s · carries %d fate(s)"
		% [
			HELD_META,
			_group(),
			int(_view.get("grants_fate_count", 0)),
		]
	)


func _group() -> String:
	var group := String(_view.get("group", ""))
	return group if group != "" else "no group"


func _teaser() -> String:
	var teaser := String(_view.get("teaser", ""))
	return teaser if teaser != "" else String(_view.get("description", ""))
