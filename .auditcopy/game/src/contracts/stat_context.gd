class_name StatContext
extends RefCounted

## Read-only view handed to StatProviders. Holds live references (not copies) so a
## provider sees current resources, traits, and affinities at query time (ADR 0002).

var base: Dictionary
var resources: Dictionary
var traits: NameList
var affinities: AffinityMap
var paths: Dictionary
var components: Dictionary
var derived: Dictionary
## The actor's meridian network. Core state on the Actor, never a module
## component (ADR 0057), so it arrives here and not through [member components].
## Untyped on purpose: `MeridianNetwork` lives in `core/` and `contracts/` must
## never depend upward on it, so a provider casts it itself.
var meridians: RefCounted = null


func _init(
	p_base: Dictionary,
	p_resources: Dictionary,
	p_traits: NameList,
	p_affinities: AffinityMap,
	p_paths: Dictionary,
	p_components: Dictionary,
	p_meridians: RefCounted = null
) -> void:
	base = p_base
	resources = p_resources
	traits = p_traits
	affinities = p_affinities
	paths = p_paths
	components = p_components
	meridians = p_meridians
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


func component(id: StringName) -> RefCounted:
	return components.get(id)


## The actor's meridian network, or null when this context was built for something
## that carries none (ADR 0057).
##
## **null is not a network worth zero.** It says the owner has no network at all,
## which is a different fact from a network nobody has trained — that one is a real
## object answering `0.0`. A caller turning this into a number must state the absent
## case in its own code, because the outcome ADR 0057 exists to end is a stat that is
## quietly 0 with nothing to point at. `component(&"meridians")` is not the read: it
## is a different lookup, and it answers null for every actor `Actor` builds.
func meridian_network() -> RefCounted:
	return meridians


func has_trait(id: StringName) -> bool:
	return traits.has(id)


func affinity(id: StringName) -> float:
	return affinities.get_value(id)
