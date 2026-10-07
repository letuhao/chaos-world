class_name BodyVitalsPanel
extends PanelContainer

## Read-only row of body-cultivation vitals. Owns every number format in the
## body screen: `%d/%d`, decimals and widths live here, never in the screen.
##
## The panel holds no game rule. It renders whatever state it is handed by
## `set_state()` and exposes `summary()` for headless tests.
##
## Contract: `summary()` returns primitives only, `{}` when empty.

var _realm_label: Label = null
var _integrity_label: Label = null
var _acupoint_label: Label = null
var _channel_label: Label = null
var _condition_label: Label = null
var _state: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render `state`, the view `BodyCultivationApi.panel_state()` produces.
## Unknown or missing keys leave the previous value alone.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	_state = state
	_render()


## The vitals this row shows, as primitives. Child row values live under their
## own key; this is the shape tests assert.
func summary() -> Dictionary:
	_bind_nodes()
	if _state.is_empty():
		return {}
	return {
		"bound": _realm_label != null,
		"realm": String(_state.get("realm", "")),
		"target": String(_state.get("target", "")),
		"stage": int(_state.get("stage", 0)),
		"integrity": float(_state.get("integrity", 0.0)),
		"integrity_maximum": float(_state.get("integrity_maximum", 0.0)),
		"progress": float(_state.get("progress", 0.0)),
		"acupoints": int(_state.get("acupoints", 0)),
		"blocked": int(_state.get("blocked", 0)),
		"average_quality": float(_state.get("average_quality", 0.0)),
		"channels": _channels(),
		"ready": bool(_state.get("ready", false)),
		"chance": float(_state.get("chance", 0.0)),
		"unmet": _unmet(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the
## headless suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _realm_label != null:
		return
	_realm_label = get_node_or_null("%RealmLabel") as Label
	_integrity_label = get_node_or_null("%IntegrityLabel") as Label
	_acupoint_label = get_node_or_null("%AcupointLabel") as Label
	_channel_label = get_node_or_null("%ChannelLabel") as Label
	_condition_label = get_node_or_null("%ConditionLabel") as Label


func _render() -> void:
	if _realm_label == null:
		return
	if _state.is_empty():
		_realm_label.text = L.t("LOC_UI_PANELS_356CFE27B0")
		_realm_label.theme_type_variation = &"MetaLabel"
		_integrity_label.text = ""
		_acupoint_label.text = ""
		_channel_label.text = ""
		_condition_label.text = ""
		return
	_realm_label.theme_type_variation = &"SectionTitle"
	_realm_label.text = (
		"Realm: %s → %s"
		% [
			String(_state.get("realm", "")),
			String(_state.get("target", "")),
		]
	)
	_integrity_label.text = (
		"Body integrity %d/%d · progress %d · strength %d"
		% [
			int(_state.get("integrity", 0.0)),
			int(_state.get("integrity_maximum", 0.0)),
			int(_state.get("progress", 0.0)),
			int(_state.get("physique", 0.0)),
		]
	)
	_acupoint_label.text = (
		"Huyệt %d (%d jammed) · quality %.2f"
		% [
			int(_state.get("acupoints", 0)),
			int(_state.get("blocked", 0)),
			float(_state.get("average_quality", 0.0)),
		]
	)
	_channel_label.text = L.t("LOC_UI_PANELS_6AF9D73707") % _channel_text()
	if bool(_state.get("ready", false)):
		_condition_label.theme_type_variation = &"OkLabel"
		_condition_label.text = (
			"Ready · breakthrough chance %d%%" % int(float(_state.get("chance", 0.0)) * 100.0)
		)
	else:
		_condition_label.theme_type_variation = &"WarnLabel"
		_condition_label.text = L.t("LOC_UI_PANELS_7B49050CD4") % ", ".join(_unmet())


func _channels() -> Array:
	var out: Array = []
	for entry in _state.get("channels", []):
		out.append(String(entry))
	return out


func _unmet() -> Array:
	var out: Array = []
	for entry in _state.get("unmet", []):
		out.append(String(entry))
	return out


func _channel_text() -> String:
	var names: Array = []
	for entry in _state.get("channels", []):
		names.append(String(entry))
	return ", ".join(names) if not names.is_empty() else "none"
