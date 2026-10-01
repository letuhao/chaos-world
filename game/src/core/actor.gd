class_name Actor
extends RefCounted

## Shared actor base: identity, stats, resources, statuses, and cultivation paths.
## Engine-agnostic — no Node/scene-tree dependency (ADR 0001, ADR 0003).

signal stats_changed
signal path_advanced(path_id: StringName, rank_id: StringName)
signal status_added(status_id: StringName)

const SCHEMA_VERSION := 1

var id: StringName
var display_name: String
var faction: StringName
var tags: Array[StringName]
var traits: Array[StringName]
var affinities: Dictionary
var relationships: Dictionary
var stats: ActorStats
var resources: Dictionary
var statuses: Array[StatusEffect]
var paths: Dictionary


func _init(p_id: StringName = &"", base: Dictionary = {}) -> void:
	id = p_id
	display_name = ""
	faction = &""
	tags = []
	traits = []
	affinities = {}
	relationships = {}
	stats = ActorStats.new(base)
	resources = {}
	statuses = []
	paths = {}


func add_resource(pool: ResourcePool) -> void:
	resources[pool.id] = pool


func resource(pool_id: StringName) -> ResourcePool:
	return resources.get(pool_id)


func add_status(status: StatusEffect) -> void:
	statuses.append(status)
	status_added.emit(status.id)


func set_path(state: PathState) -> void:
	paths[state.path_id] = state


func path(path_id: StringName) -> PathState:
	return paths.get(path_id)


func realm() -> StringName:
	for state in paths.values():
		return state.rank_id
	return &""


func to_dict() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"id": String(id),
		"display_name": display_name,
		"faction": String(faction),
		"tags": _string_array(tags),
		"traits": _string_array(traits),
		"affinities": affinities.duplicate(),
		"relationships": relationships.duplicate(),
		"base": stats.base_dict(),
		"resources": _resources_dict(),
		"paths": _paths_dict(),
	}


static func from_dict(data: Dictionary) -> Actor:
	var actor := Actor.new(StringName(data.get("id", "")), data.get("base", {}))
	actor.display_name = String(data.get("display_name", ""))
	actor.faction = StringName(data.get("faction", ""))
	for tag in data.get("tags", []):
		actor.tags.append(StringName(tag))
	for trait in data.get("traits", []):
		actor.traits.append(StringName(trait))
	actor.affinities = data.get("affinities", {}).duplicate()
	actor.relationships = data.get("relationships", {}).duplicate()
	for key in data.get("resources", {}).keys():
		actor.resources[StringName(key)] = ResourcePool.from_dict(data["resources"][key])
	for key in data.get("paths", {}).keys():
		actor.paths[StringName(key)] = PathState.from_dict(data["paths"][key])
	return actor


func _string_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


func _resources_dict() -> Dictionary:
	var out := {}
	for key in resources.keys():
		var pool: ResourcePool = resources[key]
		out[String(key)] = pool.to_dict()
	return out


func _paths_dict() -> Dictionary:
	var out := {}
	for key in paths.keys():
		var state: PathState = paths[key]
		out[String(key)] = state.to_dict()
	return out
