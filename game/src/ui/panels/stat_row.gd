class_name StatRow
extends HBoxContainer

## One labelled value, and the only place a "%d/%d" is ever formatted.
##
## Screens hand raw numbers down; this row owns the wording, the decimals and the
## width, so two screens showing the same value can never disagree about it.
##
## Contract: `summary()` is the testable surface.

const MODE_BAR := &"bar"
const MODE_PLAIN := &"plain"
## The label carries the whole line and the value column is hidden. Used by rows
## whose content is one sentence (a channel is "Lung open d0 (required)"), where
## splitting name from value would only hurt readability.
const MODE_TEXT := &"text"

var _label: Label = null
var _value: Label = null
var _bar: ProgressBar = null
var _name: String = ""
var _current: float = 0.0
var _maximum: float = 0.0
var _decimals: int = 0
var _mode: StringName = MODE_PLAIN
var _visible_bar: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Configure the row. `name` is the visible label, `current`/`maximum` the raw
## values, `decimals` how many decimal places to show, and `mode` whether to show
## a progress bar under the label.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	if state.has("name"):
		_name = String(state["name"])
	if state.has("current"):
		_current = float(state["current"])
	if state.has("maximum"):
		_maximum = float(state["maximum"])
	if state.has("decimals"):
		_decimals = maxi(0, int(state["decimals"]))
	if state.has("mode"):
		_mode = StringName(state["mode"])
	_render()


## The value as the row renders it. Empty until `set_state` supplies a name, so a
## row with nothing to say takes no space.
func summary() -> Dictionary:
	_bind_nodes()
	if _name.is_empty():
		return {}
	return {
		"name": _name,
		"current": _current,
		"maximum": _maximum,
		"decimals": _decimals,
		"mode": String(_mode),
		"bar_visible": _bar != null and _visible_bar,
		"bar_ratio": ratio(),
		"text": value_text(),
		"label_text": "" if _label == null else _label.text,
	}


## Fill fraction, clamped to 0..1. Zero when no maximum is known, so a bar never
## renders as full or empty by accident.
func ratio() -> float:
	if _maximum <= 0.0:
		return 0.0
	return clampf(_current / _maximum, 0.0, 1.0)


## Value with its unit and precision. The single formatting rule every row uses.
func value_text() -> String:
	if _maximum > 0.0:
		return "%s/%s" % [_number(_current), _number(_maximum)]
	return _number(_current)


func _number(value: float) -> String:
	if _decimals > 0:
		return "%.*f" % [_decimals, value]
	return "%d" % int(round(value))


func _bind_nodes() -> void:
	if _label != null:
		return
	_label = get_node_or_null("%StatLabel") as Label
	_value = get_node_or_null("%ValueLabel") as Label
	_bar = get_node_or_null("%StatBar") as ProgressBar


func _render() -> void:
	if _value == null:
		return
	visible = not _name.is_empty()
	_label.text = _name
	var text_only := _mode == MODE_TEXT
	_value.visible = not text_only
	_value.text = value_text()
	if _bar != null:
		_visible_bar = _mode == MODE_BAR
		_bar.visible = _visible_bar
		if _visible_bar:
			_bar.max_value = 1.0
			_bar.value = ratio()
