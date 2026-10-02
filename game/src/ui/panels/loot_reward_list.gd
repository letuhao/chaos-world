class_name LootRewardList
extends VBoxContainer

## The reward list: one row per drop of one encounter, plus the `Take all` action
## and the line that reports what the last pickup actually did.
##
## It also serves the bounded world drop container, where each row's action is
## `Reclaim` instead of `Pick up`. Both modes render the same primitive row shape,
## so the two lists cannot drift apart.
##
## The list owns every `%d`, `%s` and every refusal wording; the screen hands raw
## values and the reason id it got back from the facade.
##
## Contract: `summary()` is the testable surface.

signal pickup_requested(drop_id: String)
signal take_all_requested(encounter_id: String)

## One scene per row, composed in `loot_drop_row.tscn` rather than built in code.
const ROW_SCENE := preload("res://src/ui/panels/loot_drop_row.tscn")

const ACTION_PICKUP := "Pick up"
const ACTION_RECLAIM := "Reclaim"
## Wording for each reason the loot facade reports. The UI program owns no rule, so
## it only says what the facade decided.
const REASON_TEXT := {
	"inventory_full": "Inventory full - the drop is in the world and can be reclaimed",
	"world_drops_full": "Inventory full and the world drops are full - make room, then take it",
	"drop_already_claimed": "Already taken",
	"drop_stashed_in_world": "Already in the world - reclaim it instead",
	"claim_already_spent": "This encounter's reward is already spent",
	"unknown_reward": "No reward for that encounter",
	"unknown_drop": "That drop is no longer listed",
	"no_inventory": "The actor has no inventory",
	"unknown_definition": "The item is not defined in the content tree",
	"unknown_stash": "That world drop is no longer listed",
	"": "",
}

var _mode: StringName = &"reward"
var _encounter_id: String = ""
var _claim_token: String = ""
var _message: String = ""
var _tone: StringName = &""
var _rows: Array = []
var _take_all_enabled: bool = false
var _title_label: Label = null
var _take_all_button: Button = null
var _rows_box: VBoxContainer = null
var _message_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one reward. `reward` is a primitive reward view; `can_pick_up` is the
## enabled state the screen computed (an empty inventory slot, an actor with an
## inventory, and so on).
func show_reward(reward: Dictionary, can_pick_up: bool) -> void:
	_bind_nodes()
	_mode = &"reward"
	if reward.is_empty():
		clear()
		return
	_encounter_id = String(reward.get("encounter_id", ""))
	_claim_token = String(reward.get("claim_token", ""))
	var can_take_all: bool = can_pick_up and int(reward.get("pending_count", 0)) > 0
	_build(reward.get("drops", []), ACTION_PICKUP, can_pick_up, can_take_all)
	_render()


## Render the world drop container. Each entry is a primitive stash that carries
## the drop it belongs to.
func show_stashes(stashes: Array, can_reclaim: bool) -> void:
	_bind_nodes()
	_mode = &"stashed"
	if stashes.is_empty():
		clear()
		return
	_encounter_id = ""
	_claim_token = ""
	_build(stashes, ACTION_RECLAIM, can_reclaim, false)
	_render()


func clear() -> void:
	_bind_nodes()
	_mode = &"reward"
	_encounter_id = ""
	_claim_token = ""
	_rows = []
	_take_all_enabled = false
	_render()


## Report what a pickup or reclaim actually did, on the row it belongs to. The
## message names the drop, so a refusal is never ambiguous about what it was about.
func report_outcome(drop_id: String, reason: String, tone: StringName = &"") -> void:
	_bind_nodes()
	var text := _reason_text(reason)
	var label := _row_label(drop_id)
	_message = text if label.is_empty() else "%s: %s" % [label, text]
	_tone = tone
	_render()


func message() -> String:
	_bind_nodes()
	return _message


## The encounter this list is rendering, or "" when it is empty or in stash mode.
## The screen reads it so an action addresses the reward the player is looking at.
func encounter_id() -> String:
	_bind_nodes()
	return _encounter_id


## Everything this list shows, as primitives only: the encounter it is rendering,
## the per-row summaries, the counts, and the outcome line.
func summary() -> Dictionary:
	_bind_nodes()
	var row_summaries: Array = []
	var pending := 0
	var claimed := 0
	var stashed := 0
	for row in _rows:
		var entry := row.summary() as Dictionary
		row_summaries.append(entry)
		if bool(entry.get("claimed", false)):
			claimed += 1
		elif bool(entry.get("stashed", false)):
			stashed += 1
		elif bool(entry.get("claimable", false)):
			pending += 1
	return {
		"mode": String(_mode),
		"encounter_id": _encounter_id,
		"claim_token": _claim_token,
		"row_count": row_summaries.size(),
		"row_keys": _row_keys(),
		"rows": row_summaries,
		"pending_count": pending,
		"claimed_count": claimed,
		"stashed_count": stashed,
		"settled": pending == 0 and stashed == 0 and not row_summaries.is_empty(),
		"take_all_enabled": _take_all_enabled,
		"message": _message,
		"tone": String(_tone),
		"title": "" if _title_label == null else _title_label.text,
	}


## Give the keyboard and pad a landing spot inside this list: the first row's
## action, so a reward is reachable without a pointer.
func focus_initial() -> void:
	_bind_nodes()
	if _take_all_button != null and not _take_all_button.disabled:
		if _take_all_button.is_inside_tree():
			_take_all_button.grab_focus()
		return
	for row in _rows:
		var entry := row as LootDropRow
		entry.focus_initial()
		return


func _bind_nodes() -> void:
	if _title_label != null:
		return
	_title_label = get_node_or_null("%RewardTitle") as Label
	_take_all_button = get_node_or_null("%TakeAllButton") as Button
	_rows_box = get_node_or_null("%RewardRows") as VBoxContainer
	_message_label = get_node_or_null("%RewardMessage") as Label
	if _take_all_button != null and not _take_all_button.pressed.is_connected(_on_take_all):
		_take_all_button.pressed.connect(_on_take_all)


func _build(entries: Array, action_label: String, enabled: bool, take_all: bool) -> void:
	_rows = []
	_take_all_enabled = take_all
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.free()
	for entry in entries:
		var row = (ROW_SCENE as PackedScene).instantiate() as LootDropRow
		_rows_box.add_child(row)
		row.action_requested.connect(_on_row_action)
		row.show_drop(entry as Dictionary, action_label, enabled)
		_rows.append(row)


func _row_keys() -> Array:
	var out: Array = []
	for row in _rows:
		out.append(String((row as LootDropRow).summary().get("drop_id", "")))
	return out


## The display name of the row with `drop_id`, or "" when no row has it.
func _row_label(drop_id: String) -> String:
	for row in _rows:
		var state := (row as LootDropRow).summary()
		if String(state.get("drop_id", "")) == drop_id:
			return String(state.get("display_name", ""))
	return ""


func _reason_text(reason: String) -> String:
	return String(REASON_TEXT.get(reason, reason))


func _render() -> void:
	if _title_label == null:
		return
	_take_all_button.visible = _mode == &"reward"
	_take_all_button.disabled = not _take_all_enabled
	_message_label.text = _message
	_message_label.theme_type_variation = (
		&"WarnLabel" if _tone == &"error" else &"OkLabel" if _tone == &"ok" else &"MetaLabel"
	)
	match _mode:
		&"stashed":
			_title_label.text = "In the world (%d)" % _rows.size()
		_:
			_title_label.text = "Reward - %d drop(s), %d waiting" % [_rows.size(), _pending()]


func _pending() -> int:
	var count := 0
	for row in _rows:
		if bool((row as LootDropRow).summary().get("claimable", false)):
			count += 1
	return count


func _on_row_action(drop_id: String) -> void:
	if _mode == &"stashed":
		return
	pickup_requested.emit(drop_id)


func _on_take_all() -> void:
	take_all_requested.emit(_encounter_id)
