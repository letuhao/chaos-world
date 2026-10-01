class_name BodyCultivationApi
extends RefCounted

## Public facade for the `body_cultivation` module (ADR 0012).
## Other modules may reference ONLY this file (`api.gd`).

const BODY_INTEGRITY := BodyStats.BODY_INTEGRITY

const _COMPONENT_ID := &"body_cultivation_provider"


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	var provider := BodyProvider.new()
	actor.stats.add_provider(provider)
	actor.set_component(_COMPONENT_ID, provider)


static func provider(actor: Actor) -> BodyProvider:
	return actor.component(_COMPONENT_ID)


static func path_def() -> CultivationPathDef:
	return BodyPath.path_def()


static func _ensure_resources(actor: Actor) -> void:
	if actor.resource(BodyStats.BODY_INTEGRITY) == null:
		actor.add_resource(ResourcePool.new(BodyStats.BODY_INTEGRITY, 100.0))
