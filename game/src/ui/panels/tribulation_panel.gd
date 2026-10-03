class_name TribulationPanel
extends PanelContainer

## Read-only row for one heavenly tribulation. Owns every number format on the
## screen: `wave/max`, the rating's decimals and the survival percentage live
## here, never in the screen.
##
## The panel holds no game rule and reads no module. It renders whatever state
## `HeavenlyTribulationApi.state()` produced and exposes `summary()` so a headless
## test asserts the fight rather than the pixels.
##
## Contract: `summary()` returns primitives only, and `{}` for an empty state.

var _target_label: Label = null
var _kind_label: Label = null
var _wave_label: Label = null
var _rating_label: Label = null
var _verdict_label: Label = null
var _state: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render `state`, the view `HeavenlyTribulationApi.state()` produces. Unknown or
## missing keys leave the previous value alone.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	_state = state
	_render()


## The fight this row shows, as primitives. This is the shape tests assert.
func summary() -> Dictionary:
	_bind_nodes()
	if _state.is_empty():
		return {}
	return {
		"bound": _target_label != null,
		"owed": bool(_state.get("owed", false)),
		"target": String(_state.get("target", "")),
		"target_name": String(_state.get("target_name", "")),
		"bound_realm": String(_state.get("bound", "")),
		"type": String(_state.get("type", "")),
		"phase": String(_state.get("phase", "")),
		"wave": int(_state.get("wave", 0)),
		"max_waves": int(_state.get("max_waves", 0)),
		"difficulty": float(_state.get("difficulty", 0.0)),
		"outcome": String(_state.get("outcome", "")),
		"chance": float(_state.get("chance", 0.0)),
		"gate_open": bool(_state.get("gate_open", false)),
		"active": bool(_state.get("active", false)),
		"decided": bool(_state.get("decided", false)),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	if _target_label != null:
		return
	_target_label = get_node_or_null("%TargetLabel") as Label
	_kind_label = get_node_or_null("%KindLabel") as Label
	_wave_label = get_node_or_null("%WaveLabel") as Label
	_rating_label = get_node_or_null("%RatingLabel") as Label
	_verdict_label = get_node_or_null("%VerdictLabel") as Label


func _render() -> void:
	if _target_label == null:
		return
	if _state.is_empty():
		_target_label.text = "No tribulation"
		_target_label.theme_type_variation = &"MetaLabel"
		_kind_label.text = ""
		_wave_label.text = ""
		_rating_label.text = ""
		_verdict_label.text = ""
		return
	_target_label.theme_type_variation = &"SectionTitle"
	_target_label.text = (
		"Tribulation: %s" % String(_state.get("target_name", ""))
		if bool(_state.get("owed", false))
		else "Tribulation: none owed"
	)
	var kind := String(_state.get("type", ""))
	_kind_label.text = (
		"" if kind.is_empty() else "%s · %s" % [kind.capitalize(), String(_state.get("phase", ""))]
	)
	_wave_label.text = "Wave %d/%d" % [int(_state.get("wave", 0)), int(_state.get("max_waves", 0))]
	_rating_label.text = (
		"Rating %.2f · survival %d%%"
		% [float(_state.get("difficulty", 0.0)), int(float(_state.get("chance", 0.0)) * 100.0)]
	)
	_render_verdict()


## The one line that answers "what happened", and it is the line a player reads
## after the fight resolves. A gate that is shut and a fight that was never
## fought read differently on purpose.
func _render_verdict() -> void:
	var outcome := String(_state.get("outcome", ""))
	match outcome:
		"survived":
			_verdict_label.theme_type_variation = &"OkLabel"
			_verdict_label.text = "Survived · the gate for this realm is open"
		"failed":
			_verdict_label.theme_type_variation = &"WarnLabel"
			_verdict_label.text = "Broken · repair the body and fight it again"
		_:
			_verdict_label.theme_type_variation = &"MetaLabel"
			_verdict_label.text = _pending_text()


func _pending_text() -> String:
	if not bool(_state.get("owed", false)):
		return "No tribulation is owed below the Immortal tier"
	if bool(_state.get("gate_open", false)):
		return "The gate is open; break through"
	if bool(_state.get("has_record", false)):
		return "A tribulation is in progress"
	return "A tribulation is owed · face it"
