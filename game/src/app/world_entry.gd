class_name WorldEntry
extends Node2D

## Base script for world scenes. Handles scene entry/exit and provides
## spawn points, NPC markers, resource nodes, and enemy spawn zones.
##
## Each world tier scene extends this with tier-specific data.

@export var world_tier: StringName = &""
@export var display_name: String = ""
@export var realm_min: int = 1
@export var realm_max: int = 9

var _spawn_point: Marker2D = null
var _player: Node2D = null
var _npc_spawn_points: Array[Marker2D] = []
var _enemy_spawn_zones: Array[Area2D] = []
var _resource_nodes: Array[Area2D] = []
var _entry_points: Array[Marker2D] = []
var _exit_points: Array[Marker2D] = []
var _location_markers: Array[Marker2D] = []


func _ready() -> void:
	_bind_nodes()
	_on_enter()


func _bind_nodes() -> void:
	# No early return on `_spawn_point`. The guard made binding ORDER-dependent:
	# a `_ready()` that ran before the authored children existed left
	# `_spawn_point` null forever, because the one call that could have filled
	# it had already been skipped. Children added after `_ready()` - which a
	# headless test and a streamed scene both do - then read a null marker and
	# silently fell back to `Vector2.ZERO`.
	_spawn_point = get_node_or_null("SpawnPoint") as Marker2D
	# Each call is TYPED at the call site, because [method _collect_nodes] returns an
	# untyped `Array` and assigning one into `Array[Marker2D]` is a runtime ABORT in
	# Godot 4.7, not a parse error: `Trying to assign an array of type "Array" to a
	# variable of type "Array[Marker2D]"`. That abort killed `_bind_nodes` at the
	# first assignment, so `_resource_nodes` was never filled, `interactables()`
	# read an empty list, and every scene-authored node was invisible — while the
	# suites still reported green, because the assertions after it ran against a
	# half-initialised entry. A wrapper that returns the right type is the fix; the
	# alternative (declaring `_collect_nodes` per type) would need six overloads.
	_npc_spawn_points = _as_markers(_collect_nodes("NPCSpawnPoints", Marker2D))
	_enemy_spawn_zones = _as_areas(_collect_nodes("EnemySpawnZones", Area2D))
	_resource_nodes = _as_areas(_collect_nodes("ResourceNodes", Area2D))
	_entry_points = _as_markers(_collect_nodes("EntryPoints", Marker2D))
	_exit_points = _as_markers(_collect_nodes("ExitPoints", Marker2D))
	_location_markers = _as_markers(_collect_nodes("LocationMarkers", Marker2D))


## `_collect_nodes` answers an untyped `Array`, and these are the two typed shapes
## this file stores. The conversion is by append, not by casting the container: a
## cast does not re-type an array in GDScript, and the assignment that follows is
## the line that raises.
func _as_markers(source: Array) -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	for node in source:
		var marker := node as Marker2D
		if marker != null:
			out.append(marker)
	return out


func _as_areas(source: Array) -> Array[Area2D]:
	var out: Array[Area2D] = []
	for node in source:
		var area := node as Area2D
		if area != null:
			out.append(area)
	return out


## Every child of `group_name` that is an instance of `type`.
##
## `type` is a `Variant`, NOT a `GDScript`: every call site passes an engine
## class (`Marker2D`, `Area2D`), and those are `GDScriptNativeClass` instances.
## Declaring the parameter `GDScript` is a PARSE ERROR for an argument of that
## type, which is what stopped this file - and every script that reaches it -
## from compiling at all.
##
## `null` collects everything under the group, which is how a group of raw
## nodes is read without naming a type that does not exist yet.
func _collect_nodes(group_name: String, type: Variant = null) -> Array:
	var out: Array = []
	var group := get_node_or_null(group_name)
	if group == null:
		return out
	for child in group.get_children():
		if type == null or is_instance_of(child, type):
			out.append(child)
	return out


func _on_enter() -> void:
	pass


func _on_exit() -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_exit()


func spawn_position() -> Vector2:
	# Bind lazily when the marker is still missing. `_ready()` is the only other
	# caller of `_bind_nodes`, and it runs before a caller can attach children,
	# so a read that trusted it saw `Vector2.ZERO` for a scene that HAS an
	# authored SpawnPoint. Re-binding here makes the read self-healing and
	# idempotent rather than order-dependent.
	if _spawn_point == null:
		_bind_nodes()
	if _spawn_point != null:
		return _spawn_point.global_position
	return Vector2.ZERO


func set_player(player: Node2D) -> void:
	_player = player
	if _player != null and _spawn_point != null:
		_player.global_position = _spawn_point.global_position


# --- NPC Spawning -----------------------------------------------------------


func npc_spawn_points() -> Array[Marker2D]:
	_bind_nodes()
	return _npc_spawn_points.duplicate()


func spawn_npc(npc: Node2D, spawn_index: int = 0) -> bool:
	_bind_nodes()
	if _npc_spawn_points.is_empty():
		return false
	var idx := spawn_index % _npc_spawn_points.size()
	npc.global_position = _npc_spawn_points[idx].global_position
	add_child(npc)
	return true


# --- Enemy Spawn Zones ------------------------------------------------------


func enemy_spawn_zones() -> Array[Area2D]:
	_bind_nodes()
	return _enemy_spawn_zones.duplicate()


func spawn_enemy(enemy: Node2D, zone_index: int = 0) -> bool:
	_bind_nodes()
	if _enemy_spawn_zones.is_empty():
		return false
	var idx := zone_index % _enemy_spawn_zones.size()
	var zone := _enemy_spawn_zones[idx]
	enemy.global_position = zone.global_position
	add_child(enemy)
	return true


func random_enemy_spawn_position(zone_index: int = 0) -> Vector2:
	_bind_nodes()
	if _enemy_spawn_zones.is_empty():
		return Vector2.ZERO
	var idx := zone_index % _enemy_spawn_zones.size()
	var zone := _enemy_spawn_zones[idx]
	var shape := zone.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return zone.global_position
	var rect := shape.shape as RectangleShape2D
	if rect == null:
		return zone.global_position
	var half_size := rect.size * 0.5
	return (
		zone.global_position
		+ Vector2(randf_range(-half_size.x, half_size.x), randf_range(-half_size.y, half_size.y))
	)


# --- Resource Nodes ---------------------------------------------------------


func resource_nodes() -> Array[Area2D]:
	_bind_nodes()
	return _resource_nodes.duplicate()


func interact_with_resource(node: Area2D) -> Dictionary:
	_bind_nodes()
	if not _resource_nodes.has(node):
		return {"ok": false, "reason": "not_a_resource_node"}
	return {"ok": true, "node_name": node.name, "position": node.global_position}


# --- Entry/Exit Points ------------------------------------------------------


func entry_points() -> Array[Marker2D]:
	_bind_nodes()
	return _entry_points.duplicate()


func exit_points() -> Array[Marker2D]:
	_bind_nodes()
	return _exit_points.duplicate()


func entry_position(index: int = 0) -> Vector2:
	_bind_nodes()
	if _entry_points.is_empty():
		return Vector2.ZERO
	return _entry_points[index % _entry_points.size()].global_position


func exit_position(index: int = 0) -> Vector2:
	_bind_nodes()
	if _exit_points.is_empty():
		return Vector2.ZERO
	return _exit_points[index % _exit_points.size()].global_position


# --- Location Markers -------------------------------------------------------


func location_markers() -> Array[Marker2D]:
	_bind_nodes()
	return _location_markers.duplicate()


# --- Tier-Specific Initialization -------------------------------------------


func tier_id() -> StringName:
	return world_tier


func tier_display_name() -> String:
	return display_name


func realm_range() -> Vector2i:
	return Vector2i(realm_min, realm_max)


func is_realm_in_tier(realm: int) -> bool:
	return realm >= realm_min and realm <= realm_max


# --- Summary ----------------------------------------------------------------


func summary() -> Dictionary:
	_bind_nodes()
	return {
		"world_tier": String(world_tier),
		"display_name": display_name,
		"realm_min": realm_min,
		"realm_max": realm_max,
		"spawn_point": spawn_position(),
		"npc_spawn_count": _npc_spawn_points.size(),
		"enemy_zone_count": _enemy_spawn_zones.size(),
		"resource_node_count": _resource_nodes.size(),
		"entry_point_count": _entry_points.size(),
		"exit_point_count": _exit_points.size(),
		"location_marker_count": _location_markers.size(),
	}
