class_name MindCultivationApi
extends RefCounted

## Public facade for the `mind_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

# Public ids other modules may depend on.
const MIND_POWER := MindStats.MIND_POWER
const AWARENESS := MindStats.AWARENESS


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	actor.stats.add_provider(MindProvider.new())


static func provider(actor: Actor) -> MindProvider:
	for entry in actor.stats._providers:
		if entry is MindProvider:
			return entry as MindProvider
	return MindProvider.new()


static func path_def() -> CultivationPathDef:
	return MindPath.path_def()


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, MindStats.MIND_POWER, true)
	_add_pool(actor, MindStats.AWARENESS, false)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
