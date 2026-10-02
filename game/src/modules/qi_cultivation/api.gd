class_name QiCultivationApi
extends RefCounted

## Public facade for the `qi_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).

# Public ids other modules may depend on.
const QI := QiStats.QI

## The training step sizes a UI's Cultivate/Meditate buttons drive. Published so
## a screen reports the facade's numbers instead of hardcoding its own, which is
## what the mind path does (ADR 0043).
const CULTIVATE_STEP := 25.0
const MEDITATE_STEP := 1.0


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


# --- Read model and actions for the UI program ------------------------------


## Everything a qi panel renders, in one read. Empty when the actor is not on
## the qi path. The dantian contributes only structural state (tier, quality,
## injury); its current/capacity live in the actor's single `qi` ResourcePool.
static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return {}
	var dantian := dantian(actor)
	var pool := actor.resource(QI)
	var preview := QiBreakthroughTransaction.preview(actor)
	# The channels this realm's own gate needs, and the state they must reach.
	# Publishing them here means a screen can offer the training action without
	# reaching for the realm seed, which is a module internal (ADR 0043).
	var required_channels: Array = []
	var required_state := ""
	var gate := QiRealmSeed.for_realm(state.rank_id)
	if gate != null:
		required_state = String(gate.required_channel_state)
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
static func attempt_breakthrough(actor: Actor) -> bool:
	return QiBreakthroughTransaction.execute(actor, null)


## Raise comprehension. The only route to a realm's `comprehension_required`
## floor, so a qi path cannot advance without it.
static func meditate(actor: Actor, amount: float) -> bool:
	return QiTraining.meditate(actor, amount)


## Train one channel toward the realm's required state. The qi breakthrough gate
## demands specific channels reach `required_channel_state`, and `cultivate` never
## touches meridians, so without this a qi actor cannot satisfy its own gate.
static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	return QiTraining.train_channel(actor, meridian_id)


## Close the first wound a recovery item can heal: the dantian scar, then the
## burned channel. Consumes the realm's `recovery_item` (ADR 0031).
static func recover_next(actor: Actor) -> bool:
	var dantian := dantian(actor)
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
