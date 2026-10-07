class_name SetThresholdRow
extends PanelContainer

## One authored set threshold: how many distinct members it needs, what it
## grants, and whether it is active right now.
##
## A pure renderer. The screen hands over the threshold dictionary the module
## published and this row owns every `%s` and every decimal, so no screen ever
## formats a number. `summary()` is the testable surface.

## Decimals per magnitude unit. Rates and fractions need a third to stay
## readable at the widths the catalog allows them.
const DECIMALS := {"magnitude": 2, "rate": 3, "fraction": 3}
const ACTIVE_TEXT := "LOC_UI_PANELS_C72633F673"
const INACTIVE_TEXT := "LOC_UI_PANELS_BE51277BFD"
const TONE_ACTIVE := &"OkLabel"
const TONE_INACTIVE := &"MetaLabel"

var _threshold: Dictionary = {}
var _effect_line: String = ""
var _state_line: String = ""
var _tone: StringName = TONE_INACTIVE
var _count_label: Label = null
var _effect_label: Label = null
var _state_label: Label = null


func _init() -> void:
	_threshold = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render the threshold `view` the module published:
## `{index, count, label, active, source, options}`. An empty dictionary clears
## the row, which is what a set with no thresholds shows.
func show_threshold(view: Dictionary) -> void:
	_bind_nodes()
	_threshold = view.duplicate(true)
	_effect_line = _options_line(_threshold.get("options", []))
	_state_line = (
		"%s — %s"
		% [
			ACTIVE_TEXT if bool(_threshold.get("active", false)) else INACTIVE_TEXT,
			_requires_line(),
		]
	)
	_tone = TONE_ACTIVE if bool(_threshold.get("active", false)) else TONE_INACTIVE
	_render()


func clear() -> void:
	show_threshold({})


## Everything the row shows, as primitives only. Empty with no threshold.
func summary() -> Dictionary:
	_bind_nodes()
	if _threshold.is_empty():
		return {}
	return {
		"index": int(_threshold.get("index", 0)),
		"count": int(_threshold.get("count", 0)),
		"label": String(_threshold.get("label", "")),
		"active": bool(_threshold.get("active", false)),
		"source": String(_threshold.get("source", "")),
		"option_count": (_threshold.get("options", []) as Array).size(),
		"options": _option_values(_threshold.get("options", [])),
		"headline": _headline(),
		"effect_line": _effect_line,
		"state_line": _state_line,
		"tone": String(_tone),
		"focus_target": "SetThresholdRow",
	}


## Give the keyboard and pad a landing spot inside this row. The target is
## recorded first, because a node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	focus_mode = Control.FOCUS_ALL
	if is_inside_tree():
		grab_focus()


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite runner drives this row before a scene tree exists, so
## `_ready()` is not a dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _count_label != null:
		return
	_count_label = get_node_or_null("%CountLabel") as Label
	_effect_label = get_node_or_null("%EffectLabel") as Label
	_state_label = get_node_or_null("%StateLabel") as Label


## "Vigil Pair (2 members)". The row owns the wording and the count.
func _headline() -> String:
	if _threshold.is_empty():
		return ""
	return "%s (%d members)" % [String(_threshold.get("label", "threshold")), _required()]


## "needs 2" / "needs 5 of 5" so an inactive row still says what it is waiting on.
func _requires_line() -> String:
	var needed := _required()
	if bool(_threshold.get("active", false)):
		return L.t("LOC_UI_PANELS_B0F437BE30") % [needed, needed]
	return L.t("LOC_UI_PANELS_585DB56920") % needed


func _required() -> int:
	return int(_threshold.get("count", 0))


## One line naming every option the threshold grants, with the value it was
## authored at and the window that value had to sit inside. The window travels
## with the option, so the row never restates the magnitude policy.
func _options_line(options: Array) -> String:
	var parts: Array = []
	for option in options:
		var entry: Dictionary = option
		parts.append(_option_line(entry))
	return ", ".join(parts)


func _option_line(entry: Dictionary) -> String:
	var places := int(DECIMALS.get(String(entry.get("unit", "magnitude")), 2))
	var format := "%%.%df" % places
	var label := String(entry.get("label", entry.get("option_id", "")))
	var value := format % float(entry.get("value", 0.0))
	return (
		"%s %s (%s - %s)"
		% [
			label,
			value,
			format % float(entry.get("value_min", 0.0)),
			format % float(entry.get("value_max", 0.0)),
		]
	)


## Raw option values, so a test can assert on numbers instead of on wording.
func _option_values(options: Array) -> Array:
	var out: Array = []
	for option in options:
		var entry: Dictionary = option
		(
			out
			. append(
				{
					"option_id": String(entry.get("option_id", "")),
					"target_id": String(entry.get("target_id", "")),
					"value": float(entry.get("value", 0.0)),
					"value_min": float(entry.get("value_min", 0.0)),
					"value_max": float(entry.get("value_max", 0.0)),
				}
			)
		)
	return out


func _render() -> void:
	if _count_label == null:
		return
	_count_label.text = L.t(_headline() if not _threshold.is_empty() else "no thresholds")
	_effect_label.text = L.t(_effect_line)
	_state_label.text = L.t(_state_line)
	_state_label.theme_type_variation = _tone
