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


## BL-0951: the mind's PERFECTION at departure — the share of the realm's required
## channels refined toward its authored `channel_refinement_cap`. The mind's gate demands
## the channel STATE only (no refinement floor), so every refinement step is depth past
## the gate and the cap is the ceiling. The shape mirrors qi's measure; the measure is
## this path's own (ADR 0939 ruling 1).
static func departure_perfection(actor: Actor, realm_id: StringName) -> float:
	var seed := MindRealmSeed.for_realm(realm_id)
	if actor == null or seed == null or seed.required_meridians.is_empty():
		return 0.0
	if seed.channel_refinement_cap <= 0:
		return 0.0
	var total := 0.0
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		total += clampf(float(channel.refinement) / float(seed.channel_refinement_cap), 0.0, 1.0)
	return total / float(seed.required_meridians.size())


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	if not MindAccess.has_provider(actor, MindProvider):
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
	# The same argument for the MASTERY ledger, and it is the one that decides
	# whether the mind path has a loop: `attach` is the ONE production enrolment
	# call, so anything not reached from it is unreachable in play exactly as
	# `attach_sea` was. A ledger nothing mints is a track nothing banks.
	#
	# Reached through `MindAccess` rather than published here: the ledger is an
	# ACCESSOR over one component key, not a verb, and at fourteen public methods
	# the facade was two over `MAX_FACADE_PUBLIC_METHODS`. `access.gd` is where this
	# module keeps the things that are not verbs.
	MindAccess.attach_mastery(actor)
	# BL-0951: the tribulation prices the past realms through the carried foundation;
	# the source is injected here for the same reason the qi path injects its gate
	# kernel — `core` may not name the module that owns the record. Idempotent.
	Tribulation.set_foundation_source(Callable(FoundationApi, "tribulation_foundation"))


static func sea(actor: Actor) -> SeaOfConsciousness:
	return actor.component(SEA_COMPONENT) as SeaOfConsciousness


## Give the actor a sea, and the provider that publishes it. Idempotent in both,
## and the provider registration is NOT inside the "no component yet" branch.
##
## It used to be. `Actor.from_dict` restores components and never a `StatProvider`
## — providers are wiring the composition root and each module's `attach` install —
## so re-attaching IS how a loaded actor gets its providers back. With the early
## return, that re-attach did nothing at all for a restored actor: it arrived
## carrying a `sea` payload slot, `attach_sea` found the component and returned
## before reaching `add_provider`, and `MindStats.SEA_CAPACITY` published nothing.
## The character sheet builds its rows from `ActorStats.derived_all()`
## (`ui/screens/character_screen.gd`), so the id being absent from that map made
## the "Sea capacity" row VANISH rather than read zero — silent, and only for an
## actor the player has saved at least once (BL-0108).
##
## Registration sits after the component branch for one reason: `contribute` reads
## the sea out of the component, and a provider registered first would be asked for
## a sea that did not exist yet. Both orders invalidate correctly — `set_component`
## and `add_provider` each `mark_stats_dirty` — so this is ordering for
## readability, not for the cache.
static func attach_sea(actor: Actor) -> SeaOfConsciousness:
	var existing := sea(actor)
	if existing == null:
		var sea_component := SeaOfConsciousness.new()
		sea_component.structural_capacity = actor.stats.get_base(MindStats.SEA_CAPACITY)
		actor.set_component(SEA_COMPONENT, sea_component)
		existing = sea_component
	if not MindAccess.has_provider(actor, SeaProvider):
		actor.stats.add_provider(SeaProvider.new())
	return existing


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
	# BL-0951 / ADR 0939, S15: the foundation row. The carried foundation and the target
	# realm's authored floor, as DATA, so a screen renders met/unmet and the wall ahead
	# without reaching for the seed (ADR 0043). The wall reads the realm being ENTERED,
	# which is the one `MindAdvancement` checks (`advancement.gd:130`).
	var min_foundation := 0.0
	if state != null:
		var next_realm := ladder.next(state.rank_id)
		if next_realm != null:
			var target_seed := MindRealmSeed.for_realm(next_realm.id)
			if target_seed != null:
				min_foundation = target_seed.min_foundation
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
		"foundation": FoundationApi.foundation(actor),
		"min_foundation": min_foundation,
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


## Close the first wound a recovery item can heal: the burned channel, scanned in
## authored order so the wound the player is nearest to reading is the one closed.
## Consumes the realm's `recovery_item` (ADR 0031). Returns true when a repair
## happened, so a panel can tell a real recovery from a no-op.
##
## The mind path has no second wound to check first, unlike qi's dantian scar or
## the body's blocked huyệt: `MindTraining.recover` acts on the channel named and
## calms the sea with it, so the injured channel IS the whole selection.
static func recover_next(actor: Actor) -> bool:
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured() and MindTraining.recover(actor, def.id):
			return true
	return false


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


static func _ensure_resources(actor: Actor) -> void:
	MindAccess.add_pool(actor, MindStats.MIND_POWER, false)
	MindAccess.add_pool(actor, MindStats.AWARENESS, false)
