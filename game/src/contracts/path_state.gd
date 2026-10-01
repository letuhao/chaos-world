class_name PathState
extends RefCounted

## One actor's progress along one cultivation path (ADR 0003).

var path_id: StringName
var rank_id: StringName
var stage: int
var progress: float
var unlocked: Array[StringName]
var resources: Dictionary


func _init(p_path_id: StringName, p_rank_id: StringName = &"") -> void:
	path_id = p_path_id
	rank_id = p_rank_id
	stage = 0
	progress = 0.0
	unlocked = []
	resources = {}


func is_started() -> bool:
	return rank_id != &""


func to_dict() -> Dictionary:
	var unlocked_out: Array = []
	for value in unlocked:
		unlocked_out.append(String(value))
	return {
		"path_id": String(path_id),
		"rank_id": String(rank_id),
		"stage": stage,
		"progress": progress,
		"unlocked": unlocked_out,
	}


static func from_dict(data: Dictionary) -> PathState:
	var state := PathState.new(
		StringName(data.get("path_id", "")), StringName(data.get("rank_id", ""))
	)
	state.stage = int(data.get("stage", 0))
	state.progress = float(data.get("progress", 0.0))
	for value in data.get("unlocked", []):
		state.unlocked.append(StringName(value))
	return state
