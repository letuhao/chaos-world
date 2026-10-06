class_name HeterosisStatusRow
extends PanelContainer

## Heterosis status: spike magnitude, decay rate, carrier state, generation.
## Formats all numbers here, not in the screen.

var _view: Dictionary = {}
var _head_label: Label = null
var _spike_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


func show_status(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_render()


func clear() -> void:
	show_status({})


func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"has_heterosis": bool(_view.get("has_heterosis", false)),
		"spike_magnitude": float(_view.get("spike_magnitude", 0.0)),
		"decay_rate": float(_view.get("decay_rate", 0.0)),
		"carrier_state": bool(_view.get("carrier_state", false)),
		"generation": int(_view.get("generation", 0)),
	}


func is_filled() -> bool:
	return not _view.is_empty()


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_spike_label = get_node_or_null("%SpikeLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = "Heterosis"
	_spike_label.text = _spike_text()
	_status_label.text = _status_text()


func _spike_text() -> String:
	return (
		"Spike %.2f · Decay %.2f"
		% [
			float(_view.get("spike_magnitude", 0.0)),
			float(_view.get("decay_rate", 0.0)),
		]
	)


func _status_text() -> String:
	if bool(_view.get("carrier_state", false)):
		return "Carrier · Generation %d" % int(_view.get("generation", 0))
	return "Not a carrier"
