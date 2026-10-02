class_name Actor
extends RefCounted

## Shared actor base: identity, stats, resources, statuses, and cultivation paths.
## Engine-agnostic — no Node/scene-tree dependency (ADR 0001, ADR 0003).

signal stats_changed
signal path_advanced(path_id: StringName, rank_id: StringName)
signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)

## Schema ladder for the actor payload:
##   1 — identity, stats, resources, paths, meridians.
##   2 — tribulation, inside world, created world, ascension.
##   3 — sea, acupoints, body progress (ADR 0028).
##   4 — module-owned breakthrough attempt records (ADR 0029).
const SCHEMA_VERSION := 4

## Module-owned attempt record. Serialized as a raw dictionary so core never
## imports the module's attempt class; the mind_cultivation module rebuilds the
## typed attempt from this key on load (ADR 0029).
const ATTEMPT_MODULE_KEY := &"mind_attempt"

## Resource pools every actor carries, mapped to the derived stat that
## expresses their capacity. Core owns health and stamina because it owns the
## stats behind them; modules add their own pools (ADR 0025).
const CORE_POOL_STATS := {
	&"health": Stat.MAX_HEALTH,
	&"stamina": Stat.MAX_STAMINA,
}

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
var _syncing_resources: bool = false
## Item-state serialization hook (ADR 0027). Registered by the items module so core
## never serializes concrete item types. Null callable means "no item state".
var _item_state_serializer: Callable = Callable()


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


## Resource pools every actor carries, mapped to the derived stat that
## expresses their capacity. Core owns health and stamina because it owns the
## stats behind them; modules add their own pools (ADR 0025).
func add_resource(pool: ResourcePool) -> void:
	resources[pool.id] = pool
	if not pool.changed.is_connected(_invalidator.on_changed):
		pool.changed.connect(_invalidator.on_changed)
	mark_stats_dirty()


## Create the core health and stamina pools if absent and size them from the
## current derived capacities. A fresh pool starts full; later capacity changes
## never refill, because `set_maximum` only clamps the current value.
func attach_core_resources() -> void:
	for pool_id in CORE_POOL_STATS:
		if resources.has(pool_id):
			continue
		add_resource(ResourcePool.new(pool_id, stats.derived(CORE_POOL_STATS[pool_id])))
	_sync_core_resources()


## Resize the core pools to the derived capacities, preserving current values.
## Guarded: a pool's `changed` signal re-enters `mark_stats_dirty`, so the sync
## must not recurse.
func _sync_core_resources() -> void:
	if _syncing_resources:
		return
	_syncing_resources = true
	for pool_id in CORE_POOL_STATS:
		var pool := resources.get(pool_id) as ResourcePool
		if pool == null:
			continue
		var regen_id := Stat.HEALTH_REGEN if pool_id == &"health" else Stat.STAMINA_REGEN
		pool.regen = stats.derived(regen_id)
		pool.set_maximum(stats.derived(CORE_POOL_STATS[pool_id]))
	_syncing_resources = false


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


func _set_resource_maximum(pool_id: StringName, value: float) -> void:
	var pool := resource(pool_id)
	if pool != null:
		pool.set_maximum(value)


func mark_stats_dirty() -> void:
	stats.mark_dirty()
	if resources.has(&"health"):
		_sync_core_resources()


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
		# The attempt record has its own payload slot so the schema can version it.
		if key == ATTEMPT_MODULE_KEY:
			continue
		module_data_dict[String(key)] = module_data[key]
	# Attempt record (active or terminal) serialized as raw data; the module
	# rebuilds the typed attempt on load. Absent means "no attempt".
	var attempt_dict: Dictionary = module_data.get(ATTEMPT_MODULE_KEY, {})
	var item_state_dict: Dictionary = {}
	if not _item_state_serializer.is_null():
		item_state_dict = _item_state_serializer.call(self)
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
		"mind_attempt": attempt_dict.duplicate(true),
		"module_data": module_data_dict,
		"item_state": item_state_dict,
		"tribulation": tribulation_dict,
		"inside_world": inside_world_dict,
		"world": world_dict,
		"ascension": ascension_dict,
	}


## Register the item-state serialization hook (ADR 0027). Called by the items module
## on attach so core never references concrete item types.
func set_item_state_serializer(serializer: Callable) -> void:
	_item_state_serializer = serializer


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
	_restore_versioned(data, actor, int(data.get("version", SCHEMA_VERSION)))
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
	# Capture raw item state for the items module to restore on attach (ADR 0027).
	actor.set_module_data(&"item_state", data.get("item_state", {}))
	actor.mark_stats_dirty()
	return actor


## Restore what the payload's schema version carries. A slot added by a later
## version is simply absent from an older save, so each restore is gated and
## defaults to "nothing there" — a v2 payload loads with no sea and no attempt.
static func _restore_versioned(data: Dictionary, actor: Actor, version: int) -> void:
	if version >= 3:
		var sea_data: Dictionary = data.get("sea", {})
		if not sea_data.is_empty():
			var sea := SeaOfConsciousness.from_dict(sea_data)
			actor.set_component(&"sea_of_consciousness", sea)
			if not sea.changed.is_connected(actor._invalidator.on_changed):
				sea.changed.connect(actor._invalidator.on_changed)
	# v4 added the attempt slot; v3 and older carry no attempt at all.
	var attempt_data: Dictionary = data.get("mind_attempt", {})
	if not attempt_data.is_empty():
		actor.set_module_data(ATTEMPT_MODULE_KEY, attempt_data.duplicate(true))


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
