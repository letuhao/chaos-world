class_name CultivationPathDef
extends Resource

## Data-driven definition of one cultivation path (ADR 0003/0005/0006). Every path
## advances along the shared realm ladder; `stage_names` is this system's display
## vocabulary for the 30 realms, aligned by index. `progression_model` and
## `resource_ids` let a system plug in its own advancement and pools.

@export var id: StringName = &""
@export var display_name: String = ""
@export var stage_names: Array[String] = []
@export var progression_model: Script
@export var resource_ids: Array[StringName] = []


func has_rank(rank_id: StringName) -> bool:
	return RealmDefaults.ladder().has(rank_id)


func rank_index(rank_id: StringName) -> int:
	return RealmDefaults.ladder().index_of(rank_id)


func stage_name(rank_id: StringName) -> String:
	var ladder := RealmDefaults.ladder()
	var index := ladder.index_of(rank_id)
	if index >= 0 and index < stage_names.size():
		return stage_names[index]
	var realm: RealmDef = ladder.realm(rank_id)
	return realm.display_name if realm != null else String(rank_id)


func make_model() -> ProgressionModel:
	if progression_model != null:
		var instance: Object = progression_model.new()
		if instance is ProgressionModel:
			return instance as ProgressionModel
	return LadderProgression.new()


func ensure_resources(actor: Actor) -> void:
	for id in resource_ids:
		if actor.resource(id) == null:
			actor.add_resource(ResourcePool.new(id, 0.0))
