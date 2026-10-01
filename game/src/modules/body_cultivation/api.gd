class_name BodyCultivationApi
extends RefCounted

## Public facade for the `body_cultivation` module (ADR 0012, ADR 0015).
## Other modules may reference ONLY this file (`api.gd`).

const BODY_INTEGRITY := BodyStats.BODY_INTEGRITY

const _COMPONENT_ID := &"body_cultivation_provider"
const _ACUPOINTS_ID := &"acupoints"


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	var provider := BodyProvider.new()
	actor.stats.add_provider(provider)
	actor.set_component(_COMPONENT_ID, provider)


static func provider(actor: Actor) -> BodyProvider:
	return actor.component(_COMPONENT_ID)


static func path_def() -> CultivationPathDef:
	return BodyPath.path_def()


static func acupoints(actor: Actor) -> Array[Acupoint]:
	var acupoint_set: AcupointSet = actor.component(_ACUPOINTS_ID)
	if acupoint_set == null:
		return []
	return acupoint_set.points


static func attach_acupoints(actor: Actor) -> void:
	var points: Array[Acupoint] = AcupointDefaults.build_for_realm(actor.realm())
	actor.set_component(_ACUPOINTS_ID, AcupointSet.new(points))
	actor.stats.add_provider(AcupointProvider.new())


static func _ensure_resources(actor: Actor) -> void:
	if actor.resource(BodyStats.BODY_INTEGRITY) == null:
		actor.add_resource(ResourcePool.new(BodyStats.BODY_INTEGRITY, 100.0))
