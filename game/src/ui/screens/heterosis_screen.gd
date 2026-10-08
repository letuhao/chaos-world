class_name HeterosisScreen
extends UiScreen

## The heterosis screen: spike magnitude, decay rate, carrier state, generation.
## Read-only. A pure consumer of the `collection` facade.

const HEADER_TEXT := "LOC_UI_SCREENS_C8BFADC109"
const NO_ACTOR_TEXT := "LOC_UI_SCREENS_6E9BC19A74"

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _status_row: HeterosisStatusRow = null
var _bound: bool = false


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var heterosis: Dictionary = _codex.get("heterosis", {})
	return {
		"actor": String(_actor.id),
		"read_only": true,
		"has_heterosis": bool(heterosis.get("has_heterosis", false)),
		"spike_magnitude": float(heterosis.get("spike_magnitude", 0.0)),
		"decay_rate": float(heterosis.get("decay_rate", 0.0)),
		"carrier_state": bool(heterosis.get("carrier_state", false)),
		"generation": int(heterosis.get("generation", 0)),
		"lineage": heterosis.get("lineage", []),
	}


func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := CollectionApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_status()


func _render() -> void:
	if _header == null:
		return
	_header.text = L.t(HEADER_TEXT if _actor != null else NO_ACTOR_TEXT)
	_footer.text = L.t("LOC_UI_SCREENS_C579B64B54")


func focus_initial() -> void:
	_bind_nodes()
	if _status_row == null:
		return
	_focus_target = String(_status_row.name)
	if _status_row.is_inside_tree():
		_status_row.call(&"focus_initial")


func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%HeterosisHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_status_row = get_node_or_null("Layout/Scroll/Status") as HeterosisStatusRow
	_bound = _header != null and _status_row != null


func _fill_status() -> void:
	if _status_row == null:
		return
	var heterosis: Dictionary = _codex.get("heterosis", {})
	_status_row.show_status(heterosis)
