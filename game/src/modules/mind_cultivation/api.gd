class_name MindCultivationApi
extends RefCounted

## Public facade for the `mind_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
##
## The facade answers two questions and nothing else: what is true right now
## (`summary`, `preview`) and what can be done about it (the action functions).
## Callers never reach for `MindTraining`, `MindAdvancement` or `MindRealmSeed`
## directly, so the UI and other modules cannot drift from the enforced rules.

# Public ids other modules may depend on.
const MIND_POWER := MindStats.MIND_POWER
const AWARENESS := MindStats.AWARENESS

const SEA_COMPONENT := &"sea_of_consciousness"

# Work per activation, owned here so no screen carries a magic number.
const CULTIVATE_STEP := 10.0
const MEDITATE_STEP := 0.1


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	if not _has_provider(actor, MindProvider):
		actor.stats.add_provider(MindProvider.new())
	# The sea is part of the path, not an optional extra: the composition root's single
	# `attach` call must leave the actor ready. ADR 0095 decided exactly this for qi,
	# where `attach_dantian` existed but nothing called it and "the whole qi path was
	# inert in play".
	#
	# Without this line, `attach_sea` had ZERO callers in `res://src` -- the only
	# production enrolment path, `ActorFactory.with_mind_cultivation`, called `attach`
	# and `synchronize` and never `attach_sea`. Every actor the game built therefore had
	# no SeaOfConsciousness: `cultivate` refused at training.gd:56, `recover` refused at
	# training.gd:125, and `summary` reported `mind_power: 0.0`. Ten thousand green
	# assertions never caught it because all 38 `attach_sea` call sites are in tests,
	# where every hand-built actor attaches the sea itself.
	attach_sea(actor)


static func path_def() -> CultivationPathDef:
	return MindPath.path_def()


static func sea(actor: Actor) -> SeaOfConsciousness:
	return actor.component(SEA_COMPONENT) as SeaOfConsciousness


static func attach_sea(actor: Actor) -> SeaOfConsciousness:
	var existing := sea(actor)
	if existing != null:
		return existing
	var sea_component := SeaOfConsciousness.new()
	sea_component.structural_capacity = actor.stats.get_base(MindStats.SEA_CAPACITY)
	actor.set_component(SEA_COMPONENT, sea_component)
	if not _has_provider(actor, SeaProvider):
		actor.stats.add_provider(SeaProvider.new())
	return sea_component


## Everything a panel needs to render, as plain values. No module types cross
## the facade, so a caller cannot mutate cultivation state through this.
static func summary(actor: Actor) -> Dictionary:
	var state := actor.path(MindPath.PATH_ID)
	var sea := sea(actor)
	var ladder := RealmDefaults.ladder()
	var channels: Array[Dictionary] = []
	var required: Array[StringName] = []
	if state != null:
		var seed := MindRealmSeed.for_realm(state.rank_id)
		if seed != null:
			required.append_array(seed.required_meridians)
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		(
			channels
			. append(
				{
					"id": String(def.id),
					"name": def.display_name,
					"state": String(channel.state) if channel != null else "unknown",
					"refinement": channel.refinement if channel != null else 0,
					"injured": channel.is_injured() if channel != null else true,
					# The gate the next realm applies to this channel. Publishing it
					# here means a screen can mark the actionable rows without
					# reaching for the realm seed, which is a module internal.
					"required": required.has(def.id),
				}
			)
		)
	# The channels this realm's own gate needs, and the state they must reach.
	# The entry rule reads the *source* realm's milestones (ADR 0024), so this is
	# the current realm's list. Publishing it means a screen can offer the training
	# action without reaching for the realm seed, which is a module internal.
	var required_channels: Array = []
	var required_state := ""
	if state != null:
		var gate := MindRealmSeed.for_realm(state.rank_id)
		if gate != null:
			required_state = String(gate.required_channel_state)
			for meridian_id in gate.required_meridians:
				required_channels.append(String(meridian_id))
	return {
		"has_path": state != null,
		"rank": String(state.rank_id) if state != null else "",
		"display_name": ladder.realm(state.rank_id).display_name if state != null else "",
		"progress": state.progress if state != null else 0.0,
		"comprehension": actor.stats.get_base(Stat.COMPREHENSION),
		"mind_power": sea.current(actor) if sea != null else 0.0,
		"mind_power_max": sea.maximum(actor) if sea != null else 0.0,
		"sea_tier": String(sea.tier) if sea != null else "",
		"clarity": sea.clarity if sea != null else 0.0,
		"purity": sea.purity if sea != null else 0.0,
		"turbulence": sea.turbulence if sea != null else 0.0,
		"trained_stage": sea.trained_stage if sea != null else 0,
		"channels": channels,
		"required_channels": required_channels,
		"required_channel_state": required_state,
	}


## Entry requirements for the next realm, without consuming or rolling.
static func preview(actor: Actor) -> Dictionary:
	return MindAdvancement.preview(actor)


# --- Actions ---------------------------------------------------------------


## One session of cultivation. The step size is the facade's, not the caller's:
## a screen renders and activates, it does not decide how much work it is.
static func cultivate(actor: Actor) -> bool:
	return MindTraining.cultivate(actor, CULTIVATE_STEP)


static func meditate(actor: Actor) -> bool:
	return MindTraining.meditate(actor, MEDITATE_STEP)


static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	return MindTraining.train_channel(actor, meridian_id)


static func strengthen_sea(actor: Actor) -> bool:
	return MindTraining.strengthen_sea(actor)


static func strengthen_anchor(actor: Actor) -> bool:
	return MindTraining.strengthen_anchor(actor)


## Start then immediately resolve one breakthrough attempt. Pass an rng to make
## the roll deterministic in tests.
##
## **The body answers first (ADR 0109).** A body plan that closes the mind path, or one whose
## `realm_ceiling` sits above the realm being entered, is refused BEFORE the roll. This
## facade does NOT ask `RaceGate` itself: the refusal lives in `MindAdvancement.start`,
## the one call both this verb and `app/mind_cultivation_ui.gd`'s Breakthrough button
## make. That UI calls `MindAdvancement.try_breakthrough` DIRECTLY and skips this facade
## entirely, so a gate here alone was a gate the player could press straight past — two
## of the four authored races close mind outright, so it is the gate that actually
## bites. The refusal carries `RaceGate`'s own `{kind, id, required, actual, label}`
## entries.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	return MindAdvancement.try_breakthrough(actor, rng)


static func _has_provider(actor: Actor, type: Script) -> bool:
	for entry in actor.stats._providers:
		if entry.get_script() == type:
			return true
	return false


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, MindStats.MIND_POWER, false)
	_add_pool(actor, MindStats.AWARENESS, false)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
