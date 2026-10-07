class_name PillarRow
extends PanelContainer

## One dual cultivation pillar: name, current value, maximum, stage (1-4).
## Formats all numbers here, not in the screen.

var _view: Dictionary = {}
var _head_label: Label = null
var _value_label: Label = null
var _stage_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


func show_pillar(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_render()


func clear() -> void:
	show_pillar({})


func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"pillar_id": String(_view.get("pillar_id", "")),
		"display_name": String(_view.get("display_name", "")),
		"current": float(_view.get("current", 0.0)),
		"maximum": float(_view.get("maximum", 0.0)),
		"stage": int(_view.get("stage", 1)),
		"stage_count": int(_view.get("stage_count", 4)),
		"progress": float(_view.get("progress", 0.0)),
	}


func is_filled() -> bool:
	return not _view.is_empty()


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_value_label = get_node_or_null("%ValueLabel") as Label
	_stage_label = get_node_or_null("%StageLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = String(_view.get("display_name", ""))
	_value_label.text = _value_text()
	_stage_label.text = _stage_text()


func _value_text() -> String:
	return (
		"%.1f / %.1f"
		% [
			float(_view.get("current", 0.0)),
			float(_view.get("maximum", 0.0)),
		]
	)


func _stage_text() -> String:
	return (
		"Stage %d of %d"
		% [
			int(_view.get("stage", 1)),
			int(_view.get("stage_count", 4)),
		]
	)
