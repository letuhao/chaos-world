class_name FoundationPanel
extends PanelContainer

## Read-only foundation readout (BL-0951 / ADR 0939, S15). Renders the view
## `FoundationApi.summary()` produces: the carried foundation, the karmic-memory floor, one
## row per realm the actor has left, and — when a screen hands one over — the wall AHEAD of a
## breakthrough (met/unmet + the target realm's floor).
##
## The panel holds no game rule. It renders whatever state it is handed by `set_state()` and
## exposes `summary()` for headless tests. It owns every number format: the screen passes raw
## values, never a formatted string.
##
## Contract: `summary()` returns primitives only, `{}` when empty.

var _title_label: Label = null
var _carried_label: Label = null
var _karmic_label: Label = null
var _rows_label: Label = null
var _wall_label: Label = null
var _state: Dictionary = {}
var _wall: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render `state`, the view `FoundationApi.summary()` produces. `wall` is optional:
## `{foundation, min_foundation}` from a path's preview, so the readout can show the wall
## ahead beside the record. Unknown or missing keys read as zero.
func set_state(state: Dictionary, wall: Dictionary = {}) -> void:
	_bind_nodes()
	_state = state
	_wall = wall
	_render()


## The readout as primitives. Child rows live under their own keys; this is the shape tests
## assert.
func summary() -> Dictionary:
	_bind_nodes()
	if _state.is_empty():
		return {}
	return {
		"bound": _title_label != null,
		"foundation": float(_state.get("foundation", 0.0)),
		"karmic": float(_state.get("karmic", 0.0)),
		"count": int(_state.get("count", 0)),
		"weakest": String(_state.get("weakest", "")),
		"rows": _rows(),
		"wall": _wall_view(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless suite
## drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _title_label != null:
		return
	_title_label = get_node_or_null("%TitleLabel") as Label
	_carried_label = get_node_or_null("%CarriedLabel") as Label
	_karmic_label = get_node_or_null("%KarmicLabel") as Label
	_rows_label = get_node_or_null("%RowsLabel") as Label
	_wall_label = get_node_or_null("%WallLabel") as Label


func _render() -> void:
	if _title_label == null:
		return
	_title_label.theme_type_variation = &"SectionTitle"
	_title_label.text = L.t("LOC_UI_PANELS_FDDE6AFA94")
	if _state.is_empty():
		_carried_label.text = ""
		_karmic_label.text = ""
		_rows_label.text = ""
		_wall_label.text = ""
		return
	_carried_label.text = (
		L.t("LOC_UI_PANELS_BB0593A26D")
		% [int(float(_state.get("foundation", 0.0)) * 100.0), int(_state.get("count", 0))]
	)
	var floor := float(_state.get("karmic", 0.0))
	if floor > 0.0:
		_karmic_label.theme_type_variation = &"OkLabel"
		_karmic_label.text = L.t("LOC_UI_PANELS_91BF06B8B0") % int(floor * 100.0)
	else:
		_karmic_label.text = ""
	var rows := _rows()
	if rows.is_empty():
		_rows_label.text = L.t("LOC_UI_PANELS_7442592D40")
	else:
		var lines: Array[String] = []
		for row in rows:
			lines.append(
				(
					"%s %d%%"
					% [
						String((row as Dictionary).get("realm_id", "")),
						int(float((row as Dictionary).get("perfection", 0.0)) * 100.0)
					]
				)
			)
		_rows_label.text = "%s" % "\n".join(lines)
	var wall := _wall_view()
	if wall.is_empty():
		_wall_label.text = ""
	elif bool(wall["met"]):
		_wall_label.theme_type_variation = &"OkLabel"
		_wall_label.text = (
			L.t("LOC_UI_PANELS_087CD4A014")
			% [int(float(wall["foundation"]) * 100.0), int(float(wall["min_foundation"]) * 100.0)]
		)
	else:
		_wall_label.theme_type_variation = &"WarnLabel"
		_wall_label.text = (
			L.t("LOC_UI_PANELS_222CE37713")
			% [int(float(wall["foundation"]) * 100.0), int(float(wall["min_foundation"]) * 100.0)]
		)


func _rows() -> Array:
	var out: Array = []
	for row in _state.get("snapshots", []):
		(
			out
			. append(
				{
					"realm_id": String((row as Dictionary).get("realm_id", "")),
					"perfection": float((row as Dictionary).get("perfection", 0.0)),
				}
			)
		)
	return out


## The wall ahead, as `{foundation, min_foundation, met}`, or `{}` when the screen handed
## none over.
func _wall_view() -> Dictionary:
	if _wall.is_empty():
		return {}
	var carried := float(_wall.get("foundation", 0.0))
	var required := float(_wall.get("min_foundation", 0.0))
	return {"foundation": carried, "min_foundation": required, "met": carried >= required}
