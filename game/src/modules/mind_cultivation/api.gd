class_name MindCultivationApi
extends RefCounted

## Public facade for the `mind_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

# Public ids other modules may depend on.
const MIND_POWER := MindStats.MIND_POWER
const AWARENESS := MindStats.AWARENESS

const SEA_COMPONENT := &"sea_of_consciousness"


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	if not _has_provider(actor, MindProvider):
		actor.stats.add_provider(MindProvider.new())


static func provider(actor: Actor) -> MindProvider:
	for entry in actor.stats._providers:
		if entry is MindProvider:
			return entry as MindProvider
	return MindProvider.new()


static func path_def() -> CultivationPathDef:
	return MindPath.path_def()


static func sea(actor: Actor) -> SeaOfConsciousness:
	return actor.component(SEA_COMPONENT) as SeaOfConsciousness


static func attach_sea(actor: Actor) -> SeaOfConsciousness:
	var existing := sea(actor)
	if existing != null:
		return existing
	var sea_component := SeaOfConsciousness.new()
	sea_component.structural_capacity = actor.stats.get_base(MindStats.SEA_CAPACITY)
	actor.set_component(SEA_COMPONENT, sea_component)
	if not _has_provider(actor, SeaProvider):
		actor.stats.add_provider(SeaProvider.new())
	return sea_component


static func _has_provider(actor: Actor, type: Script) -> bool:
	for entry in actor.stats._providers:
		if entry.get_script() == type:
			return true
	return false


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, MindStats.MIND_POWER, false)
	_add_pool(actor, MindStats.AWARENESS, false)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
