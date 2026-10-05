class_name PathState
extends RefCounted

## One actor's progress along one cultivation path (ADR 0003). Observable: any
## change to rank/stage/progress/unlocked emits `changed`, so stat caches refresh.

signal changed

## The three cultivation path ids (ADR 0005 ladder, ADR 0011/0012/0013 paths).
## Declared here so a consumer that only *reads* an actor's paths — the character
## sheet, a save inspector — does not have to name a module's internals to learn
## which paths exist.
const BODY := &"body_cultivation"
const MIND := &"mind_cultivation"
const QI := &"qi_cultivation"
const ALL: Array[StringName] = [BODY, MIND, QI]

var path_id: StringName
var unlocked: NameList

var rank_id: StringName:
	get:
		return _rank_id
	set(value):
		if _rank_id == value:
			return
		_rank_id = value
		changed.emit()

var stage: int:
	get:
		return _stage
	set(value):
		if _stage == value:
			return
		_stage = value
		changed.emit()

var progress: float:
	get:
		return _progress
	set(value):
		if _progress == value:
			return
		_progress = value
		changed.emit()

var _rank_id: StringName = &""
var _stage: int = 0
var _progress: float = 0.0


func _init(p_path_id: StringName, p_rank_id: StringName = &"") -> void:
	path_id = p_path_id
	_rank_id = p_rank_id
	unlocked = NameList.new()


func is_started() -> bool:
	return rank_id != &""


func to_dict() -> Dictionary:
	return {
		"path_id": String(path_id),
		"rank_id": String(rank_id),
		"stage": stage,
		"progress": progress,
		"unlocked": unlocked.to_array(),
	}


static func from_dict(data: Dictionary) -> PathState:
	var state := PathState.new(
		StringName(data.get("path_id", "")), StringName(data.get("rank_id", ""))
	)
	state.stage = int(data.get("stage", 0))
	state.progress = float(data.get("progress", 0.0))
	state.unlocked.set_values(data.get("unlocked", []))
	return state
