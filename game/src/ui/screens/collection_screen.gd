class_name CollectionScreen
extends UiScreen

## The collection screen: 12 reward tiers, current progress, claimed status.
## Read-only except for the claim verb. A pure consumer of the `collection` facade.

const TIER_ROWS := 12
const TIER_SCENE := "res://src/ui/panels/collection_tier_row.tscn"
const HEADER_TEXT := "LOC_UI_SCREENS_CAC632BC77"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _tier_box: VBoxContainer = null
var _bound: bool = false
var _tier_rows: Array = []


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var tiers := _tier_summaries()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		"tier_count": int(_codex.get("tier_count", 0)),
		"tiers": tiers,
		"current_progress": int(_codex.get("current_progress", 0)),
		"next_tier": int(_codex.get("next_tier", 0)),
		"actions": ["claim_tier"],
		"enabled": {"claim_tier": int(_codex.get("next_tier", 0)) > 0},
	}


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := CollectionApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_tiers()


func _render() -> void:
	if _header == null:
		return
	_header.text = L.t(HEADER_TEXT if _actor != null else NO_ACTOR_TEXT)
	_footer.text = L.t("LOC_UI_SCREENS_E8D22CCA94")


func focus_initial() -> void:
	_bind_nodes()
	var target: Node = _first_filled(_tier_rows)
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
	_header = get_node_or_null("%CollectionHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_tier_box = get_node_or_null("Layout/Scroll/Tiers") as VBoxContainer
	_bound = _header != null and _tier_box != null
	if not _bound:
		return
	_tier_rows = _rows_in(_tier_box, TIER_SCENE, "Tier", TIER_ROWS)


func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as CollectionTierRow
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


func _fill_tiers() -> void:
	var tiers: Array = _codex.get("tiers", [])
	var target := RowBudget.cap(tiers.size())
	while _tier_rows.size() < target:
		var row := load(TIER_SCENE).instantiate() as Control
		row.name = "Tier%d" % _tier_rows.size()
		_tier_box.add_child(row)
		_tier_rows.append(row)
	var index := 0
	while index < _tier_rows.size():
		var row: CollectionTierRow = _tier_rows[index]
		row.show_tier(tiers[index] as Dictionary if index < tiers.size() else {})
		index += 1


func _tier_summaries() -> Array:
	var out: Array = []
	for row in _tier_rows:
		var view: Dictionary = (row as CollectionTierRow).summary()
		if not view.is_empty():
			out.append(view)
	return out
