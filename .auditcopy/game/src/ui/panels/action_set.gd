class_name ActionSet
extends VBoxContainer

## A screen's row of actions and its single result line.
##
## Generic: a screen declares which actions it has and which are currently live,
## and this renders them as buttons without knowing what they mean. It owns no
## game rule — it emits `action_requested` and the screen writes the outcome back.
##
## Contract: `summary()` is the testable surface.

signal action_requested(action: StringName)

const TONE_ERROR := &"error"
const TONE_OK := &"ok"

var _actions: Array[StringName] = []
var _labels: Dictionary = {}
var _enabled: Dictionary = {}
var _message: String = ""
var _tone: StringName = &""
var _primary: StringName = &""
var _row: HBoxContainer = null
var _message_label: Label = null
var _buttons: Dictionary = {}
var _focus_target: String = ""


func _ready() -> void:
	_bind_nodes()
	_render()


## Declare the actions this screen offers and their current state. `actions` is an
## ordered array of ids; `labels` maps id to button text; `enabled` maps id to
## whether it can run now. `primary` is the one committed action, styled apart.
## Keys absent from `enabled` default to false, so a new action is never live by
## accident.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	if state.has("actions"):
		_actions.clear()
		for action in state["actions"]:
			_actions.append(StringName(action))
	if state.has("labels"):
		_labels = {}
		for key in state["labels"]:
			_labels[String(key)] = String(state["labels"][key])
	if state.has("enabled"):
		_enabled = {}
		for key in state["enabled"]:
			_enabled[String(key)] = bool(state["enabled"][key])
	if state.has("primary"):
		_primary = StringName(state["primary"])
	if state.has("message"):
		set_message(String(state["message"]), StringName(state.get("tone", "")))
	_ensure_buttons()
	_render()


## Report the outcome of an action. `tone` is `ok`, `error`, or "" for neutral.
## Passing an empty message clears the line.
func set_message(message: String, tone: StringName = &"") -> void:
	_bind_nodes()
	_message = message
	_tone = tone
	_render()


## The first live action, so the keyboard and pad always have a landing spot.
## The target name is recorded before any grab, because a node outside a viewport
## has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for action in _actions:
		if _is_enabled(action):
			_focus(action)
			return


func summary() -> Dictionary:
	_bind_nodes()
	var enabled := {}
	var available: Array = []
	for action in _actions:
		var id := String(action)
		enabled[id] = _is_enabled(action)
		if bool(enabled[id]):
			available.append(id)
	return {
		"actions": _action_ids(),
		"enabled": enabled,
		"available": available,
		"primary": String(_primary),
		"message": _message,
		"tone": String(_tone),
		"focus_target": _focus_target,
	}


## Invoke an action by id as though its button were pressed. The headless CLI
## drives screens this way, so an LLM reaches the same code path a player does.
func request(action: StringName) -> bool:
	if not _actions.has(action) or not _is_enabled(action):
		return false
	action_requested.emit(action)
	return true


func _action_ids() -> Array:
	var out: Array = []
	for action in _actions:
		out.append(String(action))
	return out


func _bind_nodes() -> void:
	if _row != null:
		return
	_row = get_node_or_null("%ActionRow") as HBoxContainer
	_message_label = get_node_or_null("%MessageLabel") as Label


## One button per declared action, created once and reused. Buttons are data, but
## they are trivial nodes; the layout itself stays composed in the scene.
func _ensure_buttons() -> void:
	if _row == null:
		return
	for action in _actions:
		var id := String(action)
		if _buttons.has(id):
			continue
		var button := Button.new()
		button.name = "%sButton" % id.to_pascal_case()
		button.text = String(_labels.get(id, id))
		if action == _primary:
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_on_pressed.bind(action))
		_row.add_child(button)
		_buttons[id] = button


func _render() -> void:
	if _message_label != null:
		_message_label.text = _message
		_message_label.theme_type_variation = _tone_variation()
	for action in _actions:
		var button: Button = _buttons.get(String(action))
		if button != null:
			button.disabled = not _is_enabled(action)


func _is_enabled(action: StringName) -> bool:
	return bool(_enabled.get(String(action), false))


func _tone_variation() -> StringName:
	match _tone:
		TONE_ERROR:
			return &"WarnLabel"
		TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


func _focus(action: StringName) -> void:
	var button: Button = _buttons.get(String(action))
	if button == null:
		return
	_focus_target = String(button.name)
	if button.is_inside_tree():
		button.grab_focus()


func _on_pressed(action: StringName) -> void:
	action_requested.emit(action)
