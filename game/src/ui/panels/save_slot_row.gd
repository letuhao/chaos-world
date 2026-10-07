class_name SaveSlotRow
extends PanelContainer

## One journey on the save menu: who it holds, how far it got, and the two
## verbs that move it. A pure view over the `SaveApi.slot_summary` shape plus
## the screen's own title and live flag; it decides nothing and stores nothing
## beyond the last verdict, which is what the summary reports.

signal load_requested(slot: StringName)
signal erase_requested(slot: StringName)

var _status_label: Label = null
var _load_button: Button = null
var _erase_button: Button = null
var _view: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Show one slot exactly as the summary publishes it: `slot`, `title`,
## `exists`, `generation`, `difficulty`, `actor_id`, `display_name`,
## `is_live`. An empty dictionary clears the row.
func show_slot(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_render()


## Everything this row shows, primitives only. `{}` when it carries no slot,
## so a spare row in the pool is not reported as a journey.
func summary() -> Dictionary:
	_bind_nodes()
	if _view.is_empty():
		return {}
	return {
		"slot": String(_view.get("slot", "")),
		"title": String(_view.get("title", "")),
		"exists": bool(_view.get("exists", false)),
		"generation": int(_view.get("generation", 0)),
		"difficulty": String(_view.get("difficulty", "")),
		"actor_id": String(_view.get("actor_id", "")),
		"display_name": String(_view.get("display_name", "")),
		"is_live": bool(_view.get("is_live", false)),
		"can_load": can_load(),
		"can_erase": can_erase(),
	}


## The slot this row offers, or `""` when the row is empty.
func slot_id() -> StringName:
	return StringName(_view.get("slot", ""))


## Whether Load is a live control. An empty slot holds no journey, so there
## is nothing to load; the button for it would be a control with nothing
## behind it.
func can_load() -> bool:
	return not _view.is_empty() and bool(_view.get("exists", false))


## Whether Erase is a live control. Empty slots and the live journey refuse:
## the first has nothing to forget, the second is being played.
func can_erase() -> bool:
	return (
		not _view.is_empty()
		and bool(_view.get("exists", false))
		and not bool(_view.get("is_live", false))
	)


## Whether the row carries anything worth taking space for.
func is_filled() -> bool:
	return not _view.is_empty()


func _bind_nodes() -> void:
	L.localize_tree(self)
	_status_label = get_node_or_null("%StatusLabel") as Label
	_load_button = get_node_or_null("%LoadButton") as Button
	_erase_button = get_node_or_null("%EraseButton") as Button
	if _load_button != null and not _load_button.pressed.is_connected(_on_load_pressed):
		_load_button.pressed.connect(_on_load_pressed)
	if _erase_button != null and not _erase_button.pressed.is_connected(_on_erase_pressed):
		_erase_button.pressed.connect(_on_erase_pressed)


func _render() -> void:
	if _status_label != null:
		_status_label.text = L.t(_status_text())
	if _load_button != null:
		_load_button.disabled = not can_load()
	if _erase_button != null:
		_erase_button.disabled = not can_erase()


## One line naming the journey and its state. The panel owns the sentence;
## the screen never formats a slot.
func _status_text() -> String:
	if _view.is_empty():
		return ""
	var title := String(_view.get("title", ""))
	if not bool(_view.get("exists", false)):
		return L.t("LOC_UI_PANELS_DDD9458E61") % title
	var line := L.t("LOC_UI_PANELS_D63E8CC16A") % [title, int(_view.get("generation", 0))]
	var hero := String(_view.get("display_name", ""))
	if not hero.is_empty():
		line += ", %s" % hero
	if bool(_view.get("is_live", false)):
		line += " (live)."
	return line


func _on_load_pressed() -> void:
	if slot_id() != &"":
		load_requested.emit(slot_id())


func _on_erase_pressed() -> void:
	if slot_id() != &"":
		erase_requested.emit(slot_id())
