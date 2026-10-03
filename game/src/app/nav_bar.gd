class_name NavBar
extends PanelContainer

## The persistent navigation hub. One button and one digit per route, drawn from
## [ScreenRoutes], and a status line naming the live route.
##
## It is shell chrome rather than a stack screen, so it lives in `src/app/`: it is
## never pushed, never hidden, and keeps answering input while a screen owns the
## viewport. It routes only — it decides nothing. `route_requested` carries the
## route id and the composition root does the navigating, so there is exactly one
## navigation mechanism (the stack) behind the bar.
##
## Contract: `summary()` is the testable surface, primitives only.

signal route_requested(route_id: StringName)

## Buttons are authored one per slot rather than generated, so the route table is
## still the single source of truth for *what* a route is, and a table longer than
## the scene is reported instead of silently truncated. Authored with headroom over
## the current table so adding a route is a table edit first and a scene edit second.
const SLOT_COUNT := 12
const SLOT_NAME := "Slot%dButton"
const ACTIVE_VARIATION := &"PrimaryButton"
const IDLE_VARIATION := &"Button"

var _slots: Array[Button] = []
var _status: Label = null
var _routes: Array[Dictionary] = []
var _active: StringName = &""


func _ready() -> void:
	_bind_nodes()
	_publish_routes()


## Give the keyboard and pad a landing spot inside the hub, so a player who has
## drifted into a screen's own controls can always walk back out. Focus goes to the
## live route's button, which doubles as "where am I".
func focus_active() -> void:
	var button := _button_for(_active)
	if button != null and button.is_inside_tree():
		button.grab_focus()


## Mark `route_id` as the live route. The status line names it so the player never
## has to infer where they are from the button styling alone.
func set_active(route_id: StringName) -> void:
	_active = route_id
	_bind_nodes()
	for index in _slots.size():
		var button := _slots[index]
		var route: Dictionary = _routes[index] if index < _routes.size() else {}
		var live := StringName(route.get("id", "")) == route_id
		button.theme_type_variation = ACTIVE_VARIATION if live else IDLE_VARIATION
	if _status != null:
		_status.text = _status_text()


## Everything this hub shows, as primitives, so a headless run can assert the
## navigation exists without reading pixels.
func summary() -> Dictionary:
	_bind_nodes()
	var buttons: Array[Dictionary] = []
	for index in _slots.size():
		var button := _slots[index]
		var route: Dictionary = _routes[index] if index < _routes.size() else {}
		(
			buttons
			. append(
				{
					"slot": index,
					"id": String(route.get("id", "")),
					"node": String(route.get("node", "")),
					"label": String(route.get("label", "")),
					"scene": String(route.get("scene", "")),
					"key": String(route.get("key", "")),
					"action": String(ScreenRoutes.action_of(StringName(route.get("id", "")))),
					"text": button.text,
					"tooltip": button.tooltip_text,
					"visible": button.visible,
					"focus_mode": int(button.focus_mode),
					"active": StringName(route.get("id", "")) == _active,
				}
			)
		)
	return {
		"route_count": _routes.size(),
		"slot_count": _slots.size(),
		"active": String(_active),
		"status": "" if _status == null else _status.text,
		"buttons": buttons,
	}


func _unhandled_input(event: InputEvent) -> void:
	if event == null or not event.is_pressed() or event.is_echo():
		return
	for route in _routes:
		var route_id := StringName(route.get("id", ""))
		if not event.is_action_pressed(ScreenRoutes.action_of(route_id)):
			continue
		# Consumed either way: the key is a navigation decision, not an input the
		# live screen should also see.
		get_viewport().set_input_as_handled()
		route_requested.emit(route_id)
		return


func _bind_nodes() -> void:
	if not _slots.is_empty():
		return
	_status = get_node_or_null("%StatusLabel") as Label
	for index in SLOT_COUNT:
		var button := get_node_or_null(slot_unique_name(index)) as Button
		if button == null:
			continue
		_slots.append(button)
		button.pressed.connect(_on_slot_pressed.bind(index))


## The unique name of one slot's button. Built by concatenation rather than a single
## format string: `"%Slot%dButton" % i` reads as one, but `%S` is a format character,
## so `sprintf` rejects the whole string and every slot resolves to nothing.
static func slot_unique_name(index: int) -> String:
	return "%" + (SLOT_NAME % index)


## Bind one authored button per route and hide any spare slot, so the bar and the
## table always describe the same set of destinations.
func _publish_routes() -> void:
	_bind_nodes()
	_routes = ScreenRoutes.all()
	if _slots.size() != SLOT_COUNT:
		# Only a real boot can be wrong: a headless suite drives this bar before a
		# scene tree exists, and there is nothing to report yet.
		if is_inside_tree():
			push_error("NavBar: expected %d route slots, found %d" % [SLOT_COUNT, _slots.size()])
	for index in _slots.size():
		var button := _slots[index]
		var route: Dictionary = _routes[index] if index < _routes.size() else {}
		var route_id := StringName(route.get("id", ""))
		button.visible = route_id != &""
		button.text = _button_text(route)
		button.tooltip_text = String(route.get("hint", ""))
		button.theme_type_variation = IDLE_VARIATION
	set_active(ScreenRoutes.ROOT_ID)


func _button_text(route: Dictionary) -> String:
	if route.is_empty():
		return ""
	return "%s  %s" % [route.get("key", ""), route.get("label", "")]


func _status_text() -> String:
	var route := ScreenRoutes.entry(_active)
	if route.is_empty():
		return ""
	return "%s — %s" % [route.get("label", ""), route.get("hint", "")]


func _button_for(route_id: StringName) -> Button:
	for index in _slots.size():
		var route: Dictionary = _routes[index] if index < _routes.size() else {}
		if StringName(route.get("id", "")) == route_id:
			return _slots[index]
	return null


func _on_slot_pressed(index: int) -> void:
	if index >= _routes.size():
		return
	route_requested.emit(StringName(_routes[index].get("id", "")))
