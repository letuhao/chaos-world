class_name RelationshipScreen
extends UiScreen

## The relationship screen: partners, bond classes, emotional signatures, history.
## A pure consumer of the `collection` facade — it renders `CollectionApi.summary(actor)`
## and names nothing else in the module (ADR 0896).
##
## The emotional signature is derived from the bond's axes by the collection module,
## never stored or computed here.

const PARTNER_ROWS := 8
const PARTNER_SCENE := "res://src/ui/panels/partner_row.tscn"
const HEADER_TEXT := "Partners and the bonds you have earned."
const NO_ACTOR_TEXT := "No hero bound."

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _partner_box: VBoxContainer = null
var _history_box: VBoxContainer = null
var _bound: bool = false
var _partner_rows: Array = []
var _selected_partner: String = ""


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var partners := _partner_summaries()
	var history := _history_rows()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"partner_count": int(_codex.get("partner_count", 0)),
		"partners": partners,
		"selected_partner": _selected_partner,
		"selected_bond_class": _selected_bond_class(),
		"selected_emotional_signature": _selected_emotional_signature(),
		"history": history,
		"actions": ["select_partner", "view_history"],
		"enabled": {"select_partner": partners.size() > 0},
	}


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := CollectionApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_partners()
	_fill_history()


func _render() -> void:
	if _header == null:
		return
	_header.text = HEADER_TEXT if _actor != null else NO_ACTOR_TEXT
	_footer.text = "Select a partner to see their bond."


func focus_initial() -> void:
	_bind_nodes()
	var target: Node = _first_filled(_partner_rows)
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
	_header = get_node_or_null("%RelationshipHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_partner_box = get_node_or_null("Layout/Scroll/Partners") as VBoxContainer
	_history_box = get_node_or_null("Layout/Scroll/History") as VBoxContainer
	_bound = _header != null and _partner_box != null and _history_box != null
	if not _bound:
		return
	_partner_rows = _rows_in(_partner_box, PARTNER_SCENE, "Partner", PARTNER_ROWS)


func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as PartnerRow
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


func _fill_partners() -> void:
	var partners: Array = _codex.get("partners", [])
	var target := RowBudget.cap(partners.size())
	while _partner_rows.size() < target:
		var row := load(PARTNER_SCENE).instantiate() as Control
		row.name = "Partner%d" % _partner_rows.size()
		_partner_box.add_child(row)
		_partner_rows.append(row)
	var index := 0
	while index < _partner_rows.size():
		var row: PartnerRow = _partner_rows[index]
		row.show_partner(partners[index] as Dictionary if index < partners.size() else {})
		index += 1


func _fill_history() -> void:
	var history: Array = CollectionApi.history(_actor)
	var count := 0
	for entry in history:
		if count >= 10:
			break
		count += 1


func _partner_summaries() -> Array:
	var out: Array = []
	for row in _partner_rows:
		var view: Dictionary = (row as PartnerRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _history_rows() -> Array:
	return CollectionApi.history(_actor).slice(0, 10)


func _selected_bond_class() -> String:
	for partner in _codex.get("partners", []):
		if String((partner as Dictionary).get("partner_id", "")) == _selected_partner:
			return String((partner as Dictionary).get("bond_class", ""))
	return ""


func _selected_emotional_signature() -> String:
	for partner in _codex.get("partners", []):
		if String((partner as Dictionary).get("partner_id", "")) == _selected_partner:
			return String((partner as Dictionary).get("emotional_signature", ""))
	return ""
