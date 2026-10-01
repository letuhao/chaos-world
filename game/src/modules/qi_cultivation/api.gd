class_name QiCultivationApi
extends RefCounted

## Public facade for the `qi_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).

# Public ids other modules may depend on.
const QI := QiStats.QI
const QI_PURITY := QiStats.QI_PURITY


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	actor.set_component(&"meridians", actor.meridians)
	actor.stats.add_provider(QiProvider.new())


static func provider(actor: Actor) -> QiProvider:
	for p in actor.stats._providers:
		if p is QiProvider:
			return p
	return QiProvider.new()


static func path_def() -> CultivationPathDef:
	return QiPath.path_def()


static func meridians(actor: Actor) -> MeridianNetwork:
	return actor.meridians


static func dantian(actor: Actor) -> Dantian:
	return actor.component(&"dantian") as Dantian


static func attach_dantian(actor: Actor) -> Dantian:
	var existing := actor.component(&"dantian") as Dantian
	if existing != null:
		return existing
	var dantian := Dantian.new()
	dantian.structural_capacity = actor.stats.get_base(QiStats.DANTIAN_CAPACITY)
	actor.set_component(&"dantian", dantian)
	actor.stats.add_provider(DantianProvider.new())
	return dantian


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, QiStats.QI, true)
	_add_pool(actor, QiStats.QI_PURITY, true)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
