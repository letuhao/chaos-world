class_name Actor
extends RefCounted

## Shared actor base: identity, stats, resources, statuses, and cultivation paths.
## Engine-agnostic — no Node/scene-tree dependency (ADR 0001, ADR 0003).

signal stats_changed
signal path_advanced(path_id: StringName, rank_id: StringName)
signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)

const SCHEMA_VERSION := 1

var id: StringName
var display_name: String
var faction: StringName
var tags: Array[StringName]
var traits: Array[StringName]
var affinities: AffinityMap
var relationships: Dictionary
var stats: ActorStats
var resources: Dictionary
var statuses: Array[StatusEffect]
var paths: Dictionary
var _context: StatContext
var _invalidator: StatsInvalidator


func _init(p_id: StringName = &"", base: Dictionary = {}) -> void:
	id = p_id
	display_name = ""
	faction = &""
	tags = []
	traits = []
	relationships = {}
	resources = {}
	statuses = []
	paths = {}
	_invalidator = StatsInvalidator.new(self)
	affinities = AffinityMap.new()
	affinities.changed.connect(_invalidator.on_changed)
	stats = ActorStats.new(base)
	_context = StatContext.new(stats.base_ref(), resources, traits, affinities, paths)
	stats.set_context(_context)


func add_resource(pool: ResourcePool) -> void:
	resources[pool.id] = pool
	if not pool.changed.is_connected(_invalidator.on_changed):
		pool.changed.connect(_invalidator.on_changed)
	mark_stats_dirty()


func resource(pool_id: StringName) -> ResourcePool:
	return resources.get(pool_id)


func add_status(status: StatusEffect) -> void:
	statuses.append(status)
	status_added.emit(status.id)
	mark_stats_dirty()


func has_status(status_id: StringName) -> bool:
	for status in statuses:
		if status.id == status_id:
			return true
	return false


func tick_statuses(delta: float) -> void:
	var kept: Array[StatusEffect] = []
	for status in statuses:
		status.tick(delta)
		if status.is_expired():
			status_removed.emit(status.id)
		else:
			kept.append(status)
	statuses = kept


func set_relationship(partner_id: StringName, affinity: float) -> void:
	relationships[partner_id] = affinity
	mark_stats_dirty()


func affinity_with(partner_id: StringName) -> float:
	return float(relationships.get(partner_id, 0.0))


func set_affinity(element_id: StringName, value: float) -> void:
	affinities.set_value(element_id, value)


func change_resource(pool_id: StringName, delta: float) -> void:
	var pool := resource(pool_id)
	if pool != null:
		pool.change(delta)


func set_resource_maximum(pool_id: StringName, value: float) -> void:
	var pool := resource(pool_id)
	if pool != null:
		pool.set_maximum(value)


func mark_stats_dirty() -> void:
	stats.mark_dirty()


func set_path(state: PathState) -> void:
	paths[state.path_id] = state
	mark_stats_dirty()


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
		"affinities": affinities.to_dict(),
		"relationships": relationships.duplicate(),
		"base": stats.base_dict(),
		"resources": _resources_dict(),
		"paths": _paths_dict(),
	}


static func from_dict(data: Dictionary) -> Actor:
	var actor := Actor.new(StringName(data.get("id", "")), data.get("base", {}))
	actor.display_name = String(data.get("display_name", ""))
	actor.faction = StringName(data.get("faction", ""))
	for tag_id in data.get("tags", []):
		actor.tags.append(StringName(tag_id))
	for trait_id in data.get("traits", []):
		actor.traits.append(StringName(trait_id))
	actor.affinities.set_dict(data.get("affinities", {}))
	for key in data.get("relationships", {}).keys():
		actor.relationships[key] = data["relationships"][key]
	for key in data.get("resources", {}).keys():
		actor.add_resource(ResourcePool.from_dict(data["resources"][key]))
	for key in data.get("paths", {}).keys():
		actor.paths[StringName(key)] = PathState.from_dict(data["paths"][key])
	actor.mark_stats_dirty()
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
