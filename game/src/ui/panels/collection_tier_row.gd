class_name CollectionTierRow
extends PanelContainer

## One collection tier: tier number, threshold, reward fate id, claimed status.
## Formats all numbers here, not in the screen.

var _view: Dictionary = {}
var _head_label: Label = null
var _reward_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


func show_tier(view: Dictionary) -> void:
	_bind_nodes()
	_view = view.duplicate(true)
	_render()


func clear() -> void:
	show_tier({})


func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"tier_id": int(_view.get("tier_id", 0)),
		"threshold": int(_view.get("threshold", 0)),
		"reward_fate": String(_view.get("reward_fate", "")),
		"claimed": bool(_view.get("claimed", false)),
		"can_claim": bool(_view.get("can_claim", false)),
		"progress": float(_view.get("progress", 0.0)),
	}


func is_filled() -> bool:
	return not _view.is_empty()


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_reward_label = get_node_or_null("%RewardLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	if not visible:
		return
	_head_label.text = "Tier %d" % int(_view.get("tier_id", 0))
	_reward_label.text = String(_view.get("reward_fate", ""))
	_status_label.text = _status_text()


func _status_text() -> String:
	if bool(_view.get("claimed", false)):
		return "Claimed"
	if bool(_view.get("can_claim", false)):
		return "Ready to claim"
	return "Locked"
