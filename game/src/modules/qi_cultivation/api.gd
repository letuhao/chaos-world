class_name QiCultivationApi
extends RefCounted

## Public facade for the `qi_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
##
## Verbs and one read model, nothing else (ADR 0095). The accessors this module
## used to publish for itself live in `QiAccess`, which is internal: nothing
## outside the module called them, and their place on this facade is what kept
## `attach` from also attaching the dantian.

# Public ids other modules may depend on.
const QI := QiStats.QI

## The training step sizes a UI's Cultivate/Meditate buttons drive. Published so
## a screen reports the facade's numbers instead of hardcoding its own, which is
## what the mind path does (ADR 0043).
const CULTIVATE_STEP := 25.0
const MEDITATE_STEP := 1.0


## Enrol an actor on the qi path: one reservoir, the qi provider, and the
## dantian. The dantian is part of the path, not an optional extra — `cultivate`,
## `recover`, the preview and the breakthrough condition all refuse an actor
## without one — so this single call leaves the actor ready (ADR 0095). The
## meridian network is core state on the Actor and reaches `QiProvider` through
## `StatContext.meridian_network()`, so this module registers no component copy
## of it: a second, divergent source of truth for core state is exactly what
## ADR 0057 removes, and the copy made the wrong read look like a working one.
static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	actor.stats.add_provider(QiProvider.new())
	QiAccess.attach_dantian(actor)


# --- Read model and actions for the UI program ------------------------------


## Everything a qi panel renders, in one read. Empty when the actor is not on
## the qi path. The dantian contributes only structural state (tier, quality,
## injury); its current/capacity live in the actor's single `qi` ResourcePool.
static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return {}
	var dantian := QiAccess.dantian(actor)
	var pool := actor.resource(QI)
	var preview := QiBreakthroughTransaction.preview(actor)
	# The channels this realm's own gate needs, and the state and depth they must
	# reach. Publishing them here means a screen can offer the training action
	# without reaching for the realm seed, which is a module internal (ADR 0043).
	var required_channels: Array = []
	var required_state := ""
	var required_depth := 0
	var gate := QiRealmSeed.for_realm(state.rank_id)
	if gate != null:
		required_state = String(gate.required_channel_state)
		required_depth = gate.required_channel_refinement
		for meridian_id in gate.required_meridians:
			required_channels.append(String(meridian_id))
	var channels: Array[String] = []
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null:
			(
				channels
				. append(
					(
						"%s:%s/%d%s"
						% [
							def.id,
							channel.state,
							channel.refinement,
							"!" if channel.is_injured() else "",
						]
					)
				)
			)
	return {
		"realm": String(state.rank_id),
		"target": String(preview.get("target_realm", "")),
		"progress": float(state.progress),
		"qi": 0.0 if pool == null else pool.current,
		"qi_maximum": 0.0 if pool == null else pool.maximum,
		"dantian_tier": "" if dantian == null else String(dantian.tier),
		"dantian_quality": 0.0 if dantian == null else dantian.quality,
		"dantian_injured": dantian != null and dantian.injured,
		"channels": channels,
		"required_channels": required_channels,
		"required_channel_state": required_state,
		"required_channel_depth": required_depth,
		"can_attempt": bool(preview.get("can_attempt", false)),
		"chance": float(preview.get("chance", 0.0)),
		"unmet": preview.get("unmet_conditions", []),
		"costs": preview.get("costs", {}),
	}


## Fill the qi pool toward the realm's fill requirement. The training verb the
## UI's Cultivate button drives, at a step size the caller supplies.
static func cultivate(actor: Actor, amount: float) -> bool:
	return QiTraining.cultivate(actor, amount)


## Roll the breakthrough attempt. A deviation is recoverable; recover and retry.
##
## **The body answers first (ADR 0109).** A qi path the actor's race closes, or a realm above its
## authored `realm_ceiling`, is refused BEFORE the roll. This facade does NOT ask
## `RaceGate` itself: the refusal lives in `QiBreakthroughTransaction.execute`, the one
## call every qi entry point makes, so `QiAdvancement.try_breakthrough` cannot reach a
## qi realm a caller of this facade could not. The refusal carries `RaceGate`'s own
## `{kind, id, required, actual, label}` entries so the breakthrough screen can name
## the closed path or the ceiling it hit, which is the ADR 0034 rule that a gate and
## its preview must be the same wording. It is a precondition and never a modifier: a
## race can stop a breakthrough, never make one easier.
static func attempt_breakthrough(actor: Actor) -> bool:
	return QiBreakthroughTransaction.execute(actor, null)


## Raise comprehension. The only route to a realm's `comprehension_required`
## floor, so a qi path cannot advance without it.
static func meditate(actor: Actor, amount: float) -> bool:
	return QiTraining.meditate(actor, amount)


## Train one channel toward the realm's required state and depth. The qi
## breakthrough gate demands specific channels reach `required_channel_state` AND
## `required_channel_refinement`, and `cultivate` never touches meridians, so
## without this a qi actor cannot satisfy its own gate. Spends the realm's
## `training_item`, and refuses without spending it once the channel has nothing
## left to learn at this realm's cap.
static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	return QiTraining.train_channel(actor, meridian_id)


## Train the first channel that still owes the NEXT realm's gate — state or depth
## — and return its id, or `&""` when nothing is owed or no elixir is in hand.
##
## Why this is a verb and not two published predicates: a caller that picked its
## own channel had to reassemble `QiRealmSeed.channel_met` from `panel_state`'s
## ingredients, and a reassembled gate is the ADR 0044 defect — a preview and the
## action it previews disagreeing — which this path already paid for once. A
## screen owns presentation, not which channel is next.
static func train_next_channel(actor: Actor) -> StringName:
	return QiTraining.train_next_channel(actor)


## Close the first wound a recovery item can heal: the dantian scar, then the
## burned channel. Consumes the realm's `recovery_item` (ADR 0031).
static func recover_next(actor: Actor) -> bool:
	var dantian := QiAccess.dantian(actor)
	if dantian != null and dantian.injured:
		for def in MeridianDefaults.all():
			if QiTraining.recover(actor, def.id):
				return true
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured() and QiTraining.recover(actor, def.id):
			return true
	return false


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, QiStats.QI, true)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
