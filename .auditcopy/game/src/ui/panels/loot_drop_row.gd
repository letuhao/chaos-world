class_name LootDropRow
extends PanelContainer

## One drop in a reward, or one stashed drop in the world. Reads the primitive
## row the loot facade hands over and renders it: name, amount, rarity, realm and
## the resolved effect lines, plus the one action that applies to it.
##
## The row owns every `%d`, `%s` and decimal it shows — the screen hands raw values
## and never formats a number — and emits `action_requested` rather than touching
## game state itself.
##
## Contract: `summary()` is the testable surface.

signal action_requested(drop_id: String)

## Rarity display vocabulary. Presentation only; the facade speaks rarity ids.
const RARITY_LABELS := {
	&"common": "Common",
	&"magic": "Magic",
	&"rare": "Rare",
	&"legendary": "Legendary",
}

## Wording for each status a drop can be in. The row owns it so a screen reports
## the same words for the same state.
const STATUS_TEXT := {
	&"claimed": "Taken",
	&"stashed": "In the world",
	&"pending": "Waiting",
}

var _state: Dictionary = {}
var _effect_lines: Array = []
var _focus_target: String = ""
var _name_label: Label = null
var _meta_label: Label = null
var _instance_label: Label = null
var _effect_rows: VBoxContainer = null
var _action_button: Button = null
var _status_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one drop. `row` is a primitive drop view; `action_label` is the button
## wording for the action that applies (`Pick up` or `Reclaim`), and `enabled` is
## the state the screen computed. An empty row clears the row.
func show_drop(row: Dictionary, action_label: String, enabled: bool) -> void:
	_bind_nodes()
	if row.is_empty():
		clear()
		return
	_effect_lines = _effect_lines_for(row)
	_state = {
		"drop_id": String(row.get("drop_id", "")),
		"stash_id": String(row.get("stash_id", "")),
		"def_id": String(row.get("def_id", "")),
		"display_name": String(row.get("display_name", "")),
		"quantity": int(row.get("quantity", 0)),
		"stackable": bool(row.get("stackable", false)),
		"rarity": String(row.get("rarity", "")),
		"rarity_label": _rarity_label(String(row.get("rarity", ""))),
		"category": String(row.get("category", "")),
		"subcategory": String(row.get("subcategory", "")),
		"realm": String(row.get("realm", "")),
		"instance_id": String(row.get("instance_id", "")),
		"rolled_count": int(row.get("rolled_count", 0)),
		"effect_line_count": _effect_lines.size(),
		"effect_lines": _effect_lines.duplicate(),
		"claimed": bool(row.get("claimed", false)),
		"stashed": bool(row.get("stashed", false)),
		"claimable": bool(row.get("claimable", false)),
		"action": action_label,
		"action_enabled": enabled,
		"status": _status_of(row),
	}
	_render()


func clear() -> void:
	_bind_nodes()
	_effect_lines = []
	_state = {"drop_id": "", "status": "", "action": "", "action_enabled": false}
	_render()


## Everything this row shows, as primitives only.
func summary() -> Dictionary:
	_bind_nodes()
	return _state.duplicate()


func focus_initial() -> void:
	_bind_nodes()
	if _action_button != null:
		_focus_target = String(_action_button.name)
		if _action_button.is_inside_tree():
			_action_button.grab_focus()


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	if _name_label != null:
		return
	_name_label = get_node_or_null("%DropName") as Label
	_meta_label = get_node_or_null("%DropMeta") as Label
	_instance_label = get_node_or_null("%DropInstance") as Label
	_effect_rows = get_node_or_null("%DropEffects") as VBoxContainer
	_action_button = get_node_or_null("%DropAction") as Button
	_status_label = get_node_or_null("%DropStatus") as Label
	if _action_button != null and not _action_button.pressed.is_connected(_on_pressed):
		_action_button.pressed.connect(_on_pressed)


## The resolved effect lines for one drop. Each effect arrives with the value
## window it was legally rolled from, so the row never restates the magnitude
## policy.
func _effect_lines_for(row: Dictionary) -> Array:
	var lines: Array = []
	for effect in row.get("effects", []):
		var entry := effect as Dictionary
		var label := String(entry.get("label", entry.get("option_id", "")))
		var channel := "fixed" if String(entry.get("channel", "")) == "fixed" else "rolled"
		var rendered := "%s [%s] %.2f" % [label, channel, float(entry.get("value", 0.0))]
		if entry.has("value_min") and entry.has("value_max"):
			rendered += " (%.2f - %.2f)" % [float(entry["value_min"]), float(entry["value_max"])]
		lines.append(rendered)
	return lines


func _status_of(row: Dictionary) -> StringName:
	if bool(row.get("claimed", false)):
		return &"claimed"
	if bool(row.get("stashed", false)):
		return &"stashed"
	return &"pending"


func _rarity_label(rarity: String) -> String:
	return String(RARITY_LABELS.get(StringName(rarity), String(RARITY_LABELS[&"common"])))


func _render() -> void:
	if _name_label == null:
		return
	var drop_id := String(_state.get("drop_id", ""))
	_name_label.text = (
		"No drop"
		if drop_id.is_empty()
		else "%s  x%d" % [String(_state.get("display_name", drop_id)), int(_state["quantity"])]
	)
	_meta_label.text = "" if drop_id.is_empty() else _meta_text()
	_instance_label.text = "" if drop_id.is_empty() else _instance_text()
	_status_label.text = String(STATUS_TEXT.get(StringName(_state.get("status", "")), ""))
	_status_label.theme_type_variation = _status_variation()
	_action_button.text = String(_state.get("action", ""))
	# `.get`, not `[]`: `_ready` renders before any `bind()` has run, so `_state` is
	# still the empty default and every key here is absent. The two reads above
	# already tolerate that; this one did not, so a pooled row -- created fresh and
	# rendered before it is bound -- raised on the very first paint and the reward
	# list never finished building, leaving the fight's drops uncollectable.
	_action_button.disabled = not bool(_state.get("action_enabled", false))
	_fill_effects()


func _meta_text() -> String:
	var category := String(_state.get("category", ""))
	var parts: Array = [
		"%s rarity" % String(_state["rarity_label"]),
		"realm %s" % String(_state["realm"]),
	]
	if not category.is_empty():
		parts.append(category)
	if bool(_state.get("stackable", false)):
		parts.append("stacked")
	return " | ".join(parts)


func _instance_text() -> String:
	var parts: Array = ["%d rolled affix(es)" % int(_state["rolled_count"])]
	if String(_state.get("instance_id", "")) != "":
		parts.append("instance %s" % String(_state["instance_id"]))
	return " | ".join(parts)


func _status_variation() -> StringName:
	match StringName(_state.get("status", "")):
		&"claimed":
			return &"OkLabel"
		&"stashed":
			return &"WarnLabel"
		_:
			return &"MetaLabel"


func _fill_effects() -> void:
	if _effect_rows == null:
		return
	for child in _effect_rows.get_children():
		_effect_rows.remove_child(child)
		child.free()
	for line in _effect_lines:
		var label := Label.new()
		label.text = line
		label.theme_type_variation = &"EffectLabel"
		_effect_rows.add_child(label)


func _on_pressed() -> void:
	action_requested.emit(String(_state.get("drop_id", "")))
