class_name DualCultivationScreen
extends UiScreen

## The dual cultivation screen: three pillars, breakthrough gates, resonance
## combinations, active partner. A pure consumer of the `collection` facade.
##
## Resonance combinations are derived from the active partner's yin/yang balance
## against the actor's — computed in the collection module.

const PILLAR_ROWS := 3
const PILLAR_SCENE := "res://src/ui/panels/pillar_row.tscn"
const HEADER_TEXT := "Three pillars: Essence, Desire, Harmony."
const NO_ACTOR_TEXT := "No hero bound."

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _pillar_box: VBoxContainer = null
var _gate_box: VBoxContainer = null
var _bound: bool = false
var _pillar_rows: Array = []
var _active_partner: String = ""


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var pillars := _pillar_summaries()
	var gates := _gate_rows()
	var resonances := _resonance_rows()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"pillars": pillars,
		"gates": gates,
		"resonances": resonances,
		"active_partner": _active_partner,
		"can_start": _actor != null,
		"can_breakthrough": _can_breakthrough(),
		"actions": ["start_session", "end_session", "attempt_breakthrough"],
		"enabled":
		{
			"start_session": _actor != null,
			"end_session": _actor != null,
			"attempt_breakthrough": _can_breakthrough(),
		},
	}


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := CollectionApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_pillars()
	_fill_gates()


func _render() -> void:
	if _header == null:
		return
	_header.text = HEADER_TEXT if _actor != null else NO_ACTOR_TEXT
	_footer.text = "Dual cultivation opens narrative doors, not power."


func focus_initial() -> void:
	_bind_nodes()
	var target: Node = _first_filled(_pillar_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%DualCultivationHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_pillar_box = get_node_or_null("Layout/Scroll/Pillars") as VBoxContainer
	_gate_box = get_node_or_null("Layout/Scroll/Gates") as VBoxContainer
	_bound = _header != null and _pillar_box != null and _gate_box != null
	if not _bound:
		return
	_pillar_rows = _rows_in(_pillar_box, PILLAR_SCENE, "Pillar", PILLAR_ROWS)


func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as PillarRow
		if row != null:
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


func _first_filled(rows: Array) -> Node:
	for row in rows:
		if row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			return row
	return null


func _fill_pillars() -> void:
	var pillars: Array = _codex.get("pillars", [])
	var target := RowBudget.cap(pillars.size())
	while _pillar_rows.size() < target:
		var row := load(PILLAR_SCENE).instantiate() as Control
		row.name = "Pillar%d" % _pillar_rows.size()
		_pillar_box.add_child(row)
		_pillar_rows.append(row)
	var index := 0
	while index < _pillar_rows.size():
		var row: PillarRow = _pillar_rows[index]
		row.show_pillar(pillars[index] as Dictionary if index < pillars.size() else {})
		index += 1


func _fill_gates() -> void:
	pass


func _pillar_summaries() -> Array:
	var out: Array = []
	for row in _pillar_rows:
		var view: Dictionary = (row as PillarRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _gate_rows() -> Array:
	var out: Array = []
	var pillars: Array = _codex.get("pillars", [])
	for pillar in pillars:
		var p := pillar as Dictionary
		(
			out
			. append(
				{
					"gate_id": String(p.get("pillar_id", "")),
					"name": String(p.get("display_name", "")),
					"threshold": float(p.get("maximum", 0.0)),
					"current": float(p.get("current", 0.0)),
					"open": int(p.get("stage", 1)) >= 2,
				}
			)
		)
	return out


func _resonance_rows() -> Array:
	var out: Array = []
	var partners: Array = _codex.get("partners", [])
	if partners.is_empty():
		return out
	var partner: Dictionary = partners[0]
	(
		out
		. append(
			{
				"combo_id": "resonance_1",
				"name": "Resonance",
				"partner_yin_yang": 0.0,
				"actor_yin_yang": 0.0,
				"effect": "Narrative door opened",
			}
		)
	)
	return out


func _can_breakthrough() -> bool:
	var pillars: Array = _codex.get("pillars", [])
	for pillar in pillars:
		if int((pillar as Dictionary).get("stage", 1)) >= 3:
			return true
	return false
