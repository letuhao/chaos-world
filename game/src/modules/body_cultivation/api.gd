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


## Enrol an actor on the body path: the integrity reservoir, the body provider, and
## the acupoints. The meridian network is core state on the Actor and reaches
## `BodyProvider` through `StatContext.meridian_network()`, so this module registers
## no component copy of it: a second, divergent source of truth for core state is
## exactly what ADR 0057 removes, and the copy made the wrong read look like a
## working one.
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
##
## `attempt` is the id of the breakthrough attempt in flight, empty when there is
## none. A panel renders "an attempt is committed" from it and offers resolve
## rather than a fresh breakthrough, without reading a module internal.
static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return {}
	var points: AcupointSet = actor.component(_ACUPOINTS_ID)
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
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
		"attempt": String(preview.get("attempt", "")),
		"steps": STEPS,
		# The high-tier gates and the ascent, published so a screen can offer the
		# action a gate owes without restating the rule that closes it. DATA, not a
		# verb: the ascent itself is `WorldAnchor.ascend`, a core entry point `ui/`
		# may call directly (ADR 0041), so nothing here grows the facade.
		"tier_gates": _tier_gates(actor, _target_index(preview)),
		"ascent": _ascent_state(actor, _target_index(preview)),
	}


## Ladder index of the realm this actor is trying to enter, or -1 when the ladder
## has none ahead of it. Read off the preview so the gate report and the unmet list
## can never name two different targets.
static func _target_index(preview: Dictionary) -> int:
	var target := String(preview.get("target", ""))
	if target.is_empty():
		return -1
	return RealmDefaults.ladder().index_of(StringName(target))


## Each high-tier gate, as core's own predicate answers it. Four booleans rather
## than one `ready`, because they are earned in four different places and a screen
## has to know WHICH is shut to offer the right button.
##
## All true below the gate's own threshold, which is what keeps a mortal hero's row
## honest: nothing here is conditional on the tier, so nothing has to be.
static func _tier_gates(actor: Actor, target_index: int) -> Dictionary:
	if target_index < 0:
		return {}
	return {
		"tribulation": Breakthrough.tribulation_ok(actor, target_index),
		"inside_world": Breakthrough.inside_world_ok(actor, target_index),
		"world": Breakthrough.world_ok(actor, target_index),
		"ascent": Breakthrough.ascension_ok(actor, target_index),
	}


## How much of the Transcendent ascent this actor has left to walk, in the shape a
## screen renders a progress bar from: `required` (is the ascent this actor's gate at
## all), `steps`, `steps_total`, `met`, and core's own wording for what is
## outstanding. The wording is `WorldAnchor.ascension_unmet`, never a restatement
## here (ADR 0034).
static func _ascent_state(actor: Actor, target_index: int) -> Dictionary:
	var remaining := 0
	if actor.ascension != null:
		remaining = actor.ascension.steps_remaining()
	return {
		"required": target_index > 0 and not Breakthrough.ascension_ok(actor, target_index),
		"steps": remaining,
		"steps_total": AscensionState.ASCENT_STEPS,
		"met": Breakthrough.ascension_ok(actor, target_index),
		"outstanding": WorldAnchor.ascension_unmet(actor),
	}


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


## The first half of a breakthrough: validate, spend the realm pill once, and
## commit the attempt. Returns an empty view when refused — unprepared, no target
## realm, or an attempt is already in flight.
##
## This is the durable half: the pill is spent here and the record is persisted,
## so a save taken now still resolves the same attempt on reload. The resolve is
## a separate call so the trial can span a save or a UI turn.
static func begin_breakthrough(actor: Actor) -> Dictionary:
	var committed := BodyAdvancement.start_attempt(actor, null)
	if committed == null:
		return {}
	return {
		"attempt": String(committed.attempt_id),
		"source": String(committed.source_rank),
		"target": String(committed.target_rank),
		"pill": String(committed.preparation.get("pill", "")),
		"chance": float(committed.preparation.get("chance", 0.0)),
		"status": String(committed.status),
	}


## The second half: roll the committed attempt and apply its outcome. True only
## when the award was granted, so calling it again reports the same answer instead
## of paying twice. A stale attempt — one whose target realm no longer follows
## the actor, or whose tier gate a reload left shut — ends without a deviation.
static func resolve_breakthrough(actor: Actor) -> bool:
	return BodyAdvancement.resolve_attempt(actor, null)


## Roll the breakthrough attempt in one press. A deviation is recoverable;
## re-prepare and retry. This is `begin_breakthrough` then `resolve_breakthrough`
## — the same two calls, so the one-press and the save-spanning attempt cannot
## diverge.
##
## **The body answers first (ADR 0109).** A body plan that closes the body path, or one whose
## `realm_ceiling` sits below the realm being attempted, is refused BEFORE the roll and carries
## `RaceGate`'s own `{kind, id, required, actual, label}` entries, so the screen names the closed
## path or the ceiling rather than reporting a bare false.
static func attempt_breakthrough(actor: Actor) -> bool:
	var blocked := RaceGate.path_unmet(actor, PathState.BODY)
	if blocked.is_empty():
		blocked = RaceGate.realm_ceiling_unmet(actor)
	if not blocked.is_empty():
		return false
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
