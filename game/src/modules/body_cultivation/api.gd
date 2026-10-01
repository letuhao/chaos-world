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
	var rank := _body_rank(actor)
	if rank != &"":
		# Channels must exist as soon as the module is attached. Without this the
		# network stays empty until the first cultivate(), and strengthen() then
		# rejects every meridian because it cannot find the channel.
		actor.meridians.unlock_for_realm(rank)


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
	var points: Array[Acupoint] = AcupointDefaults.build_for_realm(_body_rank(actor))
	actor.set_component(_ACUPOINTS_ID, AcupointSet.new(points))
	actor.stats.add_provider(AcupointProvider.new())


## The body path's own rank. Not Actor.realm(), which returns whichever path
## happens to come first and would scope acupoints to the wrong cultivation path.
static func _body_rank(actor: Actor) -> StringName:
	var state := actor.path(BodyPath.PATH_ID)
	return &"" if state == null else state.rank_id


static func _ensure_resources(actor: Actor) -> void:
	if actor.resource(BodyStats.BODY_INTEGRITY) == null:
		actor.add_resource(ResourcePool.new(BodyStats.BODY_INTEGRITY, 100.0))
