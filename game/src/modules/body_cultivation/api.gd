class_name BodyCultivationApi
extends RefCounted

## Public facade for the `body_cultivation` module (ADR 0012, ADR 0015).
## Other modules may reference ONLY this file (`api.gd`).

const BODY_INTEGRITY := BodyStats.BODY_INTEGRITY

const _COMPONENT_ID := &"body_cultivation_provider"
const _ACUPOINTS_ID := &"acupoints"

## Step sizes for the training verbs, so a screen never hardcodes them. One
## `cultivate` step and one `meditate` step are a single press of the button.
const STEPS := {"cultivate": 25.0, "meditate": 1.0}


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


# --- Read model and actions for the UI program (ADR 0028) -------------------
#
# `ui/` is a pure consumer: it may reach this module only through this facade,
# so everything a panel renders or triggers lives here. The panel never reads a
# module internal.


## Everything a cultivation panel renders, in one read. Empty when the actor is
## not on the body path.
static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return {}
	var points: AcupointSet = actor.component(_ACUPOINTS_ID)
	var integrity := actor.resource(BODY_INTEGRITY)
	var preview := BodyAdvancement.preview(actor)
	var channels: Array[String] = []
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null:
			channels.append("%s:%s/%d" % [def.id, channel.state, channel.refinement])
	return {
		"realm": String(state.rank_id),
		"target": String(preview.get("target", &"")),
		"stage": int(state.stage),
		"progress": float(state.progress),
		"integrity": 0.0 if integrity == null else integrity.current,
		"integrity_maximum": 0.0 if integrity == null else integrity.maximum,
		"acupoints": 0 if points == null else points.points.size(),
		"blocked": 0 if points == null else points.blocked_count(),
		"average_quality": 0.0 if points == null else points.average_quality(),
		"channels": channels,
		"physique": actor.stats.get_base(Stat.PHYSIQUE),
		"ready": bool(preview.get("ready", false)),
		"chance": float(preview.get("chance", 0.0)),
		"unmet": preview.get("unmet", []),
		"steps": STEPS,
	}


## Breakthrough preview: what is true now, and what is missing (ADR 0028).
## Never mutates the actor.
static func preview(actor: Actor) -> Dictionary:
	return BodyAdvancement.preview(actor)


## One cultivation step: fills the shared reservoir, grows acupoint quality, and
## accumulates progress.
static func cultivate(actor: Actor, amount: float) -> bool:
	return BodyTraining.cultivate(actor, amount)


## One meditation step. Comprehension is the only route to the insight floor.
static func meditate(actor: Actor, amount: float) -> bool:
	return BodyTraining.meditate(actor, amount)


## Train the next channel that still has work: first the channels the current
## realm introduces, then the ones the next realm requires. Returns false when
## nothing is left to train or the realm's elixir is missing.
static func strengthen_next(actor: Actor) -> bool:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return false
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	var candidates: Array[StringName] = []
	candidates.append_array(seed.channel_training)
	candidates.append_array(seed.required_meridians)
	for meridian_id in candidates:
		if BodyTraining.strengthen(actor, meridian_id):
			return true
	return false


## Roll the breakthrough attempt. A deviation is recoverable; re-prepare and
## retry.
static func attempt_breakthrough(actor: Actor) -> bool:
	return BodyAdvancement.try_breakthrough(actor, null)


## Close the first wound a recovery item can heal: a blocked huyệt first (it
## names its own channel), then an injured channel. Consumes the realm's
## recovery item. Returns true when a repair happened, so a panel can tell a
## real recovery from a no-op.
static func recover_next(actor: Actor) -> bool:
	var points: AcupointSet = actor.component(_ACUPOINTS_ID)
	if points != null:
		for point in points.points:
			if not point.blocked:
				continue
			var meridian_id := AcupointDefaults.meridian_of(point.id)
			if meridian_id != &"" and BodyTraining.recover(actor, meridian_id):
				return true
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured() and BodyTraining.recover(actor, def.id):
			return true
	return false


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
		# Drop the raw copy so the next save serializes the live set, not stale data.
		actor.set_module_data(&"acupoints", {})
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
