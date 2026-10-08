class_name ActionBar
extends VBoxContainer

## Action row for the selected item: the slot selector, the four item actions,
## and the validation line every rejected action reports into.
##
## The bar owns no game rule. It renders whatever enabled-state the screen hands
## it and emits `action_requested`; the screen calls the facade and writes the
## outcome back with `set_state()`.
##
## Contract: `summary()` is the testable surface.

signal action_requested(action: StringName, payload: Dictionary)
signal slot_changed(slot: StringName)

const ACTIONS: Array[StringName] = [
	&"use",
	&"equip",
	&"unequip",
	&"generate",
	&"save",
	&"load",
	&"teardown",
]
## Canonical equipment slots offered by the selector. Presentation list, kept in
## step with the items module's slot ids.
const SLOT_IDS: Array[StringName] = [
	&"weapon",
	&"armor",
	&"accessory_a",
	&"accessory_b",
	&"artifact",
]
const TONE_ERROR := &"error"
const TONE_OK := &"ok"

## Wording for each successful outcome. The screen hands raw values; this panel
## owns every `%s`/`%d` and the width of the message.
const OUTCOME_TEXT := {
	&"used": "LOC_UI_PANELS_21550AD71D",
	&"equipped": "LOC_UI_PANELS_B77339B967",
	&"unequipped": "LOC_UI_PANELS_BA64D822BA",
	&"generated": "LOC_UI_PANELS_42A8FBA959",
	&"saved": "LOC_UI_PANELS_82FCF35221",
	&"loaded": "LOC_UI_PANELS_D32EC875C9",
	&"torn_down": "LOC_UI_PANELS_TORN_DOWN",
}

var _enabled: Dictionary = {}
var _slot: StringName = SLOT_IDS[0]
var _message: String = ""
var _tone: StringName = &""
var _outcome: StringName = &""
var _outcome_count: int = 0
var _outcome_name: String = ""
var _outcome_slot: String = ""
var _focus_target: String = ""
var _slot_option: OptionButton = null
var _use_button: Button = null
var _equip_button: Button = null
var _unequip_button: Button = null
var _generate_button: Button = null
var _save_button: Button = null
var _load_button: Button = null
var _teardown_button: Button = null
var _message_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render the enabled-state, slot and validation line the screen computed.
## `state` keys: `enabled` (Dictionary), `slot` (String), `message` (String),
## `tone` (String). Unknown or missing keys leave the previous value alone.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	if state.has("enabled"):
		_enabled = state["enabled"]
	if state.has("slot"):
		set_slot(StringName(state["slot"]))
	# An empty message clears a rejection but must not wipe an outcome the
	# screen already reported through `report()`.
	if String(state.get("message", "")) != "":
		_message = String(state["message"])
		_outcome = &""
	elif not _outcome.is_empty() and state.has("tone"):
		_tone = StringName(state["tone"])
	if state.has("tone") and _outcome.is_empty():
		_tone = StringName(state["tone"])
	_render()


## Report a successful action. The screen hands raw values; this panel owns the
## `%d`, the wording and the width, so screens never format numbers.
## `kind` is one of `used`, `equipped`, `unequipped`, `generated`, `saved`,
## `loaded`; `count` is a slot count, `item_name` the item's display name and
## `slot` the equipment slot id.
func report(kind: StringName, count: int = 0, item_name: String = "", slot: String = "") -> void:
	_bind_nodes()
	_outcome = kind
	_outcome_count = count
	_outcome_name = item_name
	_outcome_slot = slot
	_tone = TONE_OK
	_render()


func clear_outcome() -> void:
	_outcome = &""
	_outcome_count = 0
	_outcome_name = ""
	_outcome_slot = ""


func _outcome_text() -> String:
	var template: String = OUTCOME_TEXT.get(_outcome, "")
	match _outcome:
		&"equipped":
			return L.t(template) % [_outcome_name, _outcome_slot]
		&"unequipped":
			return L.t(template) % _outcome_slot
		&"saved", &"loaded":
			return L.t(template) % _outcome_count
		&"used", &"generated":
			return L.t(template) % _outcome_name
		_:
			return ""


## Point the slot selector at `slot`. Unknown ids keep the current selection so
## the bar never shows a slot the facade would reject outright.
func set_slot(slot: StringName) -> void:
	_bind_nodes()
	if not SLOT_IDS.has(slot):
		return
	_slot = slot
	if _slot_option != null and _slot_option.selected != SLOT_IDS.find(slot):
		_slot_option.select(SLOT_IDS.find(slot))


## The slot the player will equip into.
func selected_slot() -> StringName:
	return _slot


## What the bar currently offers: which actions are live, the slot list, the
## validation line and where the pad/keyboard focus sits.
func summary() -> Dictionary:
	_bind_nodes()
	var enabled := {}
	var available: Array = []
	for action in ACTIONS:
		enabled[String(action)] = _is_enabled(action)
		if bool(enabled[String(action)]):
			available.append(String(action))
	var slots: Array = []
	for slot in SLOT_IDS:
		slots.append(String(slot))
	return {
		"enabled": enabled,
		"available": available,
		"slots": slots,
		"slot": String(_slot),
		"message": _outcome_text() if not _outcome.is_empty() else _message,
		"tone": String(_tone),
		"focus_target": _focus_target,
		"focused_action": _focused_action(),
	}


## Give the keyboard and pad a landing spot inside this panel: the first live
## action, so the bar stays reachable even when nothing is selectable. The target
## is recorded first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _slot_option == null:
		return
	for action in ACTIONS:
		if _is_enabled(action):
			_focus(action)
			return
	_focus(&"use")


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this bar before a scene tree exists, so `_ready()`
## is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _slot_option != null:
		return
	_slot_option = get_node_or_null("%SlotOption") as OptionButton
	_use_button = get_node_or_null("%UseButton") as Button
	_equip_button = get_node_or_null("%EquipButton") as Button
	_unequip_button = get_node_or_null("%UnequipButton") as Button
	_generate_button = get_node_or_null("%GenerateButton") as Button
	_save_button = get_node_or_null("%SaveButton") as Button
	_load_button = get_node_or_null("%LoadButton") as Button
	_teardown_button = get_node_or_null("%TeardownButton") as Button
	_message_label = get_node_or_null("%MessageLabel") as Label
	if _slot_option != null and not _slot_option.item_selected.is_connected(_on_slot_selected):
		_slot_option.item_selected.connect(_on_slot_selected)
	for action in ACTIONS:
		var button := _button(action)
		if button != null and not button.pressed.is_connected(_on_pressed.bind(action)):
			button.pressed.connect(_on_pressed.bind(action))
	_fill_slots()


func _focus(action: StringName) -> void:
	var button := _button(action)
	if button == null:
		return
	_focus_target = String(button.name)
	if button.is_inside_tree():
		button.grab_focus()


func _button(action: StringName) -> Button:
	match action:
		&"use":
			return _use_button
		&"equip":
			return _equip_button
		&"unequip":
			return _unequip_button
		&"generate":
			return _generate_button
		&"save":
			return _save_button
		&"teardown":
			return _teardown_button
		_:
			return _load_button


func _is_enabled(action: StringName) -> bool:
	return bool(_enabled.get(String(action), false))


func _render() -> void:
	if _use_button == null:
		return
	_use_button.disabled = not _is_enabled(&"use")
	_equip_button.disabled = not _is_enabled(&"equip")
	_unequip_button.disabled = not _is_enabled(&"unequip")
	_generate_button.disabled = not _is_enabled(&"generate")
	_save_button.disabled = not _is_enabled(&"save")
	_load_button.disabled = not _is_enabled(&"load")
	var outcome := _outcome_text()
	_message_label.text = L.t(outcome if outcome != "" else _message)
	_message_label.theme_type_variation = _tone_variation()


func _tone_variation() -> StringName:
	match _tone:
		TONE_ERROR:
			return &"WarnLabel"
		TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


func _focused_action() -> String:
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var focused := viewport.gui_get_focus_owner()
	if focused == null:
		return ""
	for action in ACTIONS:
		if _button(action) == focused:
			return String(action)
	return ""


## Items are data; the selector widget itself is composed in
## `action_bar.tscn`.
func _fill_slots() -> void:
	if _slot_option == null:
		return
	_slot_option.clear()
	for slot in SLOT_IDS:
		_slot_option.add_item(String(slot))
	_slot_option.select(0)


func _on_pressed(action: StringName) -> void:
	action_requested.emit(action, {"slot": String(_slot)})


func _on_slot_selected(index: int) -> void:
	if index < 0 or index >= SLOT_IDS.size():
		return
	_slot = SLOT_IDS[index]
	slot_changed.emit(_slot)
