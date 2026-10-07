class_name CreationBranchRow
extends PanelContainer

## One way of arriving in the world, offered BEFORE the hero exists: the arrival's
## own words, the body it arrives in, and the cultivation paths that body can never
## take.
##
## ## This row holds one button, and it is not a picker
##
## It is the only control on this screen that commits, and it names ONE origin — the
## one this row is. A player reads three rows, picks how they arrived, and the
## creation layer earns that origin exactly once (ADR 0065). There is no list of
## seventeen fates here and no control that grants one, which is the difference
## between this row and `DestinyBranchRow`: the codex publishes no button at all
## because a held destiny is a report, and this row publishes exactly one because a
## creation answer is a question, not a destination.
##
## The row owns every format it shows — the body name, the closed-path wording, the
## "already closed" mark — so the screen never renders a number or a joined list.
## `summary()` is the testable surface, and `{}` when the row carries nothing.

## The press. Carries the arrival id ONLY; the screen hands it to
## `CharacterCreationFlow`, which is the single place a destiny is ever earned.
signal committed(origin_id: StringName)

const LOCKED_HEAD := "Closed"
const OPEN_META := "This is how you arrive. The other two close for good."
const LOCKED_META := "This arrival is closed and never reopens."

var _view: Dictionary = {}
var _head: String = ""
var _description: String = ""
var _bearing: String = ""
var _body_line: String = ""
var _paths_line: String = ""
var _meta: String = ""
var _head_label: Label = null
var _description_label: Label = null
var _bearing_label: Label = null
var _body_label: Label = null
var _paths_label: Label = null
var _meta_label: Label = null
var _choose_button: Button = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one candidate exactly as `CharacterCreationFlow.candidates()` publishes
## it: `{id, display_name, description, bearing, available, unmet, race,
## race_name, closed_paths, open_paths, ...}`. An empty dictionary clears the row,
## which is what a spare row in the pool shows.
func show_branch(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_description = ""
		_bearing = ""
		_body_line = ""
		_paths_line = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var available := bool(_view.get("available", false))
	var authored_name := String(_view.get("display_name", ""))
	_head = authored_name if authored_name != "" else LOCKED_HEAD
	_description = String(_view.get("description", ""))
	_bearing = String(_view.get("bearing", ""))
	_body_line = _body_text(_view)
	_paths_line = _paths_text(_view)
	_meta = OPEN_META if available else LOCKED_META
	_render()


func clear() -> void:
	show_branch({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"id": origin_id(),
		"available": bool(_view.get("available", false)),
		"named": String(_view.get("display_name", "")) != "",
		"display_name": String(_view.get("display_name", "")),
		"group": String(_view.get("group", "")),
		"race": String(_view.get("race", "")),
		"race_name": String(_view.get("race_name", "")),
		"closed_paths": _strings(_view.get("closed_paths", [])),
		"open_paths": _strings(_view.get("open_paths", [])),
		"unmet_count": (_view.get("unmet", []) as Array).size(),
		"arrival_fates": _strings(_view.get("arrival_fates", [])),
		"can_commit": can_commit(),
		"head": _head,
		"description": _description,
		"bearing": _bearing,
		"body_line": _body_line,
		"paths_line": _paths_line,
		"meta": _meta,
		"focus_target": "CreationBranchRow",
	}


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


## The arrival this row offers, or `""` when the row is empty.
func origin_id() -> String:
	return String(_view.get("id", ""))


## Whether the confirm button on this row is a live control. The real gate's
## answer, carried down rather than re-derived: a row nobody can commit is shown
## greyed out, and a test can tell "closed" from "no button".
func can_commit() -> bool:
	return is_filled() and bool(_view.get("available", false))


## Give the keyboard and pad a landing spot. The confirm button when the arrival
## is open, so focus lands where a player would act. Recorded first, because a node
## outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _choose_button != null and _choose_button.is_inside_tree():
		_choose_button.grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_description_label = get_node_or_null("%DescriptionLabel") as Label
	_bearing_label = get_node_or_null("%BearingLabel") as Label
	_body_label = get_node_or_null("%BodyLabel") as Label
	_paths_label = get_node_or_null("%PathsLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label
	_choose_button = get_node_or_null("%ChooseButton") as Button
	if _choose_button != null and not _choose_button.pressed.is_connected(_on_choose):
		_choose_button.pressed.connect(_on_choose)


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_tone()
	_description_label.text = _description
	_description_label.visible = not _description.is_empty()
	_description_label.theme_type_variation = &"EffectLabel"
	_bearing_label.text = _bearing
	_bearing_label.visible = not _bearing.is_empty()
	_body_label.text = _body_line
	_paths_label.text = _paths_line
	_meta_label.text = _meta
	if _choose_button != null:
		_choose_button.disabled = not can_commit()
		_choose_button.text = _choose_text()


## The body this arrival arrives in, named as a player reads it. `race_name` is
## authored copy; the id is the fallback rather than the primary, because a player
## reads "Stoneborn" and never "stoneborn".
func _body_text(view: Dictionary) -> String:
	var named := String(view.get("race_name", ""))
	var raw := String(view.get("race", ""))
	return "Arrives in a %s body." % (named if named != "" else raw)


## What that body costs, in the only vocabulary a player has. An arrival with no
## closed path says so rather than printing an empty list.
func _paths_text(view: Dictionary) -> String:
	var closed := _strings(view.get("closed_paths", []))
	if closed.is_empty():
		return "This body closes no cultivation path."
	return "This body cannot cultivate: %s." % ", ".join(closed)


func _choose_text() -> String:
	if not can_commit():
		return "Closed"
	return "Arrive this way"


func _head_tone() -> StringName:
	return &"DestinyNameLabel" if can_commit() else &"DestinyLockedLabel"


## The press is a REQUEST, never a grant. The row emits the arrival id it was
## built with and the screen asks the creation flow, so the only place a destiny is
## earned is the layer that owns the earn.
func _on_choose() -> void:
	var id := origin_id()
	if id == "" or not can_commit():
		return
	committed.emit(StringName(id))


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
