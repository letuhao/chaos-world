class_name LootRewardPicker
extends VBoxContainer

## Which outstanding reward the player is looking at.
##
## A run leaves one payload per defeated boss, and rule E3 spawns the next boss as
## soon as the previous one dies — so several payloads can be unclaimed at the same
## time. Without a control that names them, every reward after the first exists in
## the world with nothing on screen addressing it and nothing the player can pick
## up. This selector is that control: one entry per outstanding payload, and the
## screen renders whichever one is selected.
##
## Presentation only. The screen hands the primitive reward views and this panel
## owns the wording it writes onto the selector.
##
## Contract: `summary()` is the testable surface.

signal reward_selected(encounter_id: String)

## Shown when nothing is waiting to be taken.
const NONE_TEXT := "No reward waiting"

var _rewards: Array = []
var _encounter_id: String = ""
var _title_label: Label = null
var _reward_option: OptionButton = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Offer every outstanding reward, keeping `keep_encounter_id` selected when it is
## still there. An empty list clears the selector, which is what makes "nothing is
## waiting" a state the player can see rather than a stale row.
func show_rewards(rewards: Array, keep_encounter_id: String = "") -> void:
	_bind_nodes()
	_rewards = rewards.duplicate()
	_encounter_id = _resolve_selection(keep_encounter_id)
	_render()


## The encounter whose payload is on screen, or "" when none is outstanding.
func encounter_id() -> String:
	_bind_nodes()
	return _encounter_id


## The primitive reward view currently selected, or `{}` when there is none.
func selected_reward() -> Dictionary:
	_bind_nodes()
	if _encounter_id.is_empty():
		return {}
	for reward in _rewards:
		if String((reward as Dictionary).get("encounter_id", "")) == _encounter_id:
			return reward as Dictionary
	return {}


func summary() -> Dictionary:
	_bind_nodes()
	var labels: Array = []
	for reward in _rewards:
		labels.append(_label_for(reward as Dictionary))
	var selected := _rewards.find(selected_reward())
	return {
		"reward_count": _rewards.size(),
		"encounter_id": _encounter_id,
		"encounter_ids": _encounter_ids(),
		"selected_index": selected,
		"option_count": _reward_option.item_count if _reward_option != null else labels.size(),
		"labels": labels,
		"selected_label": _label_for(selected_reward()),
		"has_selection": not _encounter_id.is_empty(),
		"pending_drops": _pending_total(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	if _title_label != null:
		return
	_title_label = get_node_or_null("%RewardPickerTitle") as Label
	_reward_option = get_node_or_null("%RewardOption") as OptionButton
	if _reward_option != null and not _reward_option.item_selected.is_connected(_on_item_selected):
		_reward_option.item_selected.connect(_on_item_selected)


func _render() -> void:
	if _title_label == null:
		return
	_title_label.text = _title_text()
	if _reward_option == null:
		return
	_reward_option.clear()
	var selected := -1
	var index := 0
	for reward in _rewards:
		_reward_option.add_item(_label_for(reward as Dictionary))
		if String((reward as Dictionary).get("encounter_id", "")) == _encounter_id:
			selected = index
		index += 1
	_reward_option.disabled = _rewards.is_empty()
	if selected >= 0:
		_reward_option.select(selected)


## Keep the caller's choice when it is still outstanding, otherwise fall back to
## the first payload. Never invents an encounter the facade did not report.
func _resolve_selection(keep_encounter_id: String) -> String:
	if not keep_encounter_id.is_empty() and _has(keep_encounter_id):
		return keep_encounter_id
	if _rewards.is_empty():
		return ""
	return String((_rewards[0] as Dictionary).get("encounter_id", ""))


func _has(encounter_id: String) -> bool:
	for reward in _rewards:
		if String((reward as Dictionary).get("encounter_id", "")) == encounter_id:
			return true
	return false


## The encounter ids in selector order, so a reader (or a test) can address an entry
## by what it means rather than by its position in a formatted label.
func _encounter_ids() -> Array:
	var out: Array = []
	for reward in _rewards:
		out.append(String((reward as Dictionary).get("encounter_id", "")))
	return out


func _label_for(reward: Dictionary) -> String:
	if reward.is_empty():
		return ""
	return (
		"%s - %d drop(s), %d waiting"
		% [
			String(reward.get("boss_id", reward.get("encounter_id", ""))),
			int(reward.get("drop_count", 0)),
			int(reward.get("pending_count", 0)),
		]
	)


func _title_text() -> String:
	if _rewards.is_empty():
		return NONE_TEXT
	return "Rewards waiting (%d)" % _rewards.size()


func _pending_total() -> int:
	var total := 0
	for reward in _rewards:
		total += int((reward as Dictionary).get("pending_count", 0))
	return total


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _rewards.size():
		return
	_encounter_id = String((_rewards[index] as Dictionary).get("encounter_id", ""))
	reward_selected.emit(_encounter_id)
