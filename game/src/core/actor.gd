class_name Actor
extends RefCounted

## Shared actor base: identity, stats, resources, statuses, and cultivation paths.
## Engine-agnostic — no Node/scene-tree dependency (ADR 0001, ADR 0003).

signal stats_changed
signal path_advanced(path_id: StringName, rank_id: StringName)
signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)

const SCHEMA_VERSION := 3

var id: StringName
var display_name: String
var faction: StringName
var tags: Array[StringName]
var traits: NameList
var affinities: AffinityMap
var relationships: Dictionary
var components: Dictionary
var module_data: Dictionary
var stats: ActorStats
var resources: Dictionary
var statuses: Array[StatusEffect]
var paths: Dictionary
var meridians: MeridianNetwork
var tribulation: Tribulation = null
var inside_world: InsideWorld = null
var world: WorldState = null
var ascension: AscensionState:
	set(value):
		ascension = value
		if ascension != null:
			components[&"ascension"] = ascension
		if stats != null:
			mark_stats_dirty()
var _context: StatContext
var _invalidator: StatsInvalidator


func _init(p_id: StringName = &"", base: Dictionary = {}) -> void:
	id = p_id
	display_name = ""
	faction = &""
	tags = []
	relationships = {}
	components = {}
	module_data = {}
	resources = {}
	statuses = []
	paths = {}
	meridians = MeridianNetwork.new()
	_invalidator = StatsInvalidator.new(self)
	traits = NameList.new()
	traits.changed.connect(_invalidator.on_changed)
	affinities = AffinityMap.new()
	affinities.changed.connect(_invalidator.on_changed)
	stats = ActorStats.new(base)
	_context = StatContext.new(stats.base_ref(), resources, traits, affinities, paths, components)
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


func set_component(id: StringName, component: RefCounted) -> void:
	components[id] = component
	mark_stats_dirty()


func component(id: StringName) -> RefCounted:
	return components.get(id)


func set_module_data(id: StringName, data: Dictionary) -> void:
	module_data[id] = data


func get_module_data(id: StringName) -> Dictionary:
	return module_data.get(id, {})


func set_path(state: PathState) -> void:
	paths[state.path_id] = state
	if not state.changed.is_connected(_invalidator.on_changed):
		state.changed.connect(_invalidator.on_changed)
	mark_stats_dirty()


func path(path_id: StringName) -> PathState:
	return paths.get(path_id)


func realm() -> StringName:
	for state in paths.values():
		return state.rank_id
	return &""


func to_dict() -> Dictionary:
	var tribulation_dict: Dictionary = {}
	if tribulation != null:
		tribulation_dict = tribulation.to_dict()
	var inside_world_dict: Dictionary = {}
	if inside_world != null:
		inside_world_dict = inside_world.to_dict()
	var world_dict: Dictionary = {}
	if world != null:
		world_dict = world.to_dict()
	var ascension_dict: Dictionary = {}
	if ascension != null:
		ascension_dict = ascension.to_dict()
	var dantian_dict: Dictionary = {}
	var dantian := component(&"dantian") as Dantian
	if dantian != null:
		dantian_dict = dantian.to_dict()
	var sea_dict: Dictionary = {}
	var sea := component(&"sea_of_consciousness") as SeaOfConsciousness
	if sea != null:
		sea_dict = sea.to_dict()
	# Acupoint data is serialized as raw dictionaries so core doesn't import
	# module classes. The body_cultivation module restores the typed set on load.
	var acupoints_dict: Dictionary = {}
	var acupoint_set: RefCounted = component(&"acupoints")
	if acupoint_set != null and acupoint_set.get("points") != null:
		for point in acupoint_set.points:
			acupoints_dict[String(point.id)] = point.to_dict()
	# Body progress (completed realm strengthening) serialized as raw data.
	var body_progress_dict: Dictionary = {}
	var body_progress: RefCounted = component(&"body_progress")
	if body_progress != null and body_progress.get("completed") != null:
		for realm_id in body_progress.completed:
			body_progress_dict[String(realm_id)] = true
	var module_data_dict: Dictionary = {}
	for key in module_data.keys():
		module_data_dict[String(key)] = module_data[key]
	return {
		"version": SCHEMA_VERSION,
		"id": String(id),
		"display_name": display_name,
		"faction": String(faction),
		"tags": _string_array(tags),
		"traits": traits.to_array(),
		"affinities": affinities.to_dict(),
		"relationships": relationships.duplicate(),
		"base": stats.base_dict(),
		"resources": _resources_dict(),
		"paths": _paths_dict(),
		"meridians": meridians.to_dict(),
		"dantian": dantian_dict,
		"sea": sea_dict,
		"acupoints": acupoints_dict,
		"body_progress": body_progress_dict,
		"module_data": module_data_dict,
		"tribulation": tribulation_dict,
		"inside_world": inside_world_dict,
		"world": world_dict,
		"ascension": ascension_dict,
	}


static func from_dict(data: Dictionary) -> Actor:
	var actor := Actor.new(StringName(data.get("id", "")), data.get("base", {}))
	actor.display_name = String(data.get("display_name", ""))
	actor.faction = StringName(data.get("faction", ""))
	for tag_id in data.get("tags", []):
		actor.tags.append(StringName(tag_id))
	for trait_id in data.get("traits", []):
		actor.traits.add(StringName(trait_id))
	actor.affinities.set_dict(data.get("affinities", {}))
	for key in data.get("relationships", {}).keys():
		actor.relationships[key] = data["relationships"][key]
	for key in data.get("resources", {}).keys():
		actor.add_resource(ResourcePool.from_dict(data["resources"][key]))
	for key in data.get("paths", {}).keys():
		var state := PathState.from_dict(data["paths"][key])
		if not state.changed.is_connected(actor._invalidator.on_changed):
			state.changed.connect(actor._invalidator.on_changed)
		actor.paths[StringName(key)] = state
	actor.meridians = MeridianNetwork.from_dict(data.get("meridians", {}))
	if not actor.meridians.changed.is_connected(actor._invalidator.on_changed):
		actor.meridians.changed.connect(actor._invalidator.on_changed)
	var dantian_data: Dictionary = data.get("dantian", {})
	if not dantian_data.is_empty():
		var dantian := Dantian.from_dict(dantian_data)
		actor.set_component(&"dantian", dantian)
		if not dantian.changed.is_connected(actor._invalidator.on_changed):
			dantian.changed.connect(actor._invalidator.on_changed)
	var sea_data: Dictionary = data.get("sea", {})
	if not sea_data.is_empty():
		var sea := SeaOfConsciousness.from_dict(sea_data)
		actor.set_component(&"sea_of_consciousness", sea)
		if not sea.changed.is_connected(actor._invalidator.on_changed):
			sea.changed.connect(actor._invalidator.on_changed)
	# Restore raw acupoint data; the body_cultivation module builds the typed set.
	var acupoints_data: Dictionary = data.get("acupoints", {})
	if not acupoints_data.is_empty():
		actor.set_module_data(&"acupoints", acupoints_data.duplicate())
	# Restore body progress (completed realm strengthening).
	var body_progress_data: Dictionary = data.get("body_progress", {})
	if not body_progress_data.is_empty():
		actor.set_module_data(&"body_progress", body_progress_data.duplicate())
	# Restore generic module data (raw dictionaries owned by modules).
	for key in data.get("module_data", {}).keys():
		actor.set_module_data(StringName(key), data["module_data"][key])
	var tribulation_data: Dictionary = data.get("tribulation", {})
	if not tribulation_data.is_empty():
		actor.tribulation = Tribulation.from_dict(tribulation_data)
	var inside_world_data: Dictionary = data.get("inside_world", {})
	if not inside_world_data.is_empty():
		actor.inside_world = InsideWorld.from_dict(inside_world_data)
	var world_data: Dictionary = data.get("world", {})
	if not world_data.is_empty():
		actor.world = WorldState.from_dict(world_data)
	var ascension_data: Dictionary = data.get("ascension", {})
	if not ascension_data.is_empty():
		actor.ascension = AscensionState.from_dict(ascension_data)
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
