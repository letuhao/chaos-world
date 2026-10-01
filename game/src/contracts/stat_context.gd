class_name StatContext
extends RefCounted

## Read-only view handed to StatProviders. Holds live references (not copies) so a
## provider sees current resources, traits, and affinities at query time (ADR 0002).

var base: Dictionary
var resources: Dictionary
var traits: Array[StringName]
var affinities: AffinityMap
var paths: Dictionary
var derived: Dictionary


func _init(
	p_base: Dictionary,
	p_resources: Dictionary,
	p_traits: Array[StringName],
	p_affinities: AffinityMap,
	p_paths: Dictionary
) -> void:
	base = p_base
	resources = p_resources
	traits = p_traits
	affinities = p_affinities
	paths = p_paths
	derived = {}


func base_value(id: StringName) -> float:
	return float(base.get(id, 0.0))


func value(id: StringName) -> float:
	if derived.has(id):
		return float(derived[id])
	return float(base.get(id, 0.0))


func resource(id: StringName) -> ResourcePool:
	return resources.get(id)


func path(path_id: StringName) -> PathState:
	return paths.get(path_id)


func has_trait(id: StringName) -> bool:
	return id in traits


func affinity(id: StringName) -> float:
	return affinities.get_value(id)
