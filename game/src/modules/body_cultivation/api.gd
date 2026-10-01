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
	# Attach the progress tracker, restoring from saved data if present.
	var saved_progress: Dictionary = actor.get_module_data(&"body_progress")
	if not saved_progress.is_empty():
		actor.set_component(&"body_progress", BodyProgress.from_dict(saved_progress))
		actor.set_module_data(&"body_progress", {})
	elif actor.component(&"body_progress") == null:
		actor.set_component(&"body_progress", BodyProgress.new())
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
	var existing: AcupointSet = actor.component(_ACUPOINTS_ID)
	if existing != null:
		# Idempotent: preserve existing state, just synchronize with current realm.
		existing.synchronize(_body_rank(actor))
		var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
		if integrity != null:
			existing.set_pool(integrity)
		return
	# Restore from raw saved data if present (set by Actor.from_dict).
	var saved: Dictionary = actor.get_module_data(&"acupoints")
	if not saved.is_empty():
		var points: Array[Acupoint] = []
		for key in saved.keys():
			points.append(Acupoint.from_dict(saved[key]))
		actor.set_component(_ACUPOINTS_ID, AcupointSet.new(points))
		actor.set_component(&"acupoints_data", null)
		actor.stats.add_provider(AcupointProvider.new())
		return
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
