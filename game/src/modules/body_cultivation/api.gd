class_name BodyCultivationApi
extends RefCounted

## Public facade for the `body_cultivation` module (ADR 0012, ADR 0015).
## Other modules may reference ONLY this file (`api.gd`).

const BODY_INTEGRITY := BodyStats.BODY_INTEGRITY

const _COMPONENT_ID := &"body_cultivation_provider"
const _ACUPOINTS_ID := &"acupoints"

## The practice ledger's component key. Weapon mastery and material-art mastery
## are ONE component, deliberately: a body that has two ledgers can be made to
## disagree about which half of its practice it has, and the two halves are one
## loop (swing the thing, reshape with it).
const PRACTICE_ID := &"body_practice"

## Step sizes for the training verbs, so a screen never hardcodes them. One
## `cultivate` step and one `meditate` step are a single press of the button.
const STEPS := {"cultivate": 25.0, "meditate": 1.0}

## The bag every material art pays its matter out of. A reshape asks for three or
## four units of ore, so the stock capacity (24) refuses the shape the whole
## material track depends on — `_ITEMS.consume_item` is all-or-nothing and
## `_stock` in the arts suite adds four times the price. This is a GATE the body
## buys into, never a rule imposed on it.
const MATERIAL_CAPACITY := 128


## Enrol an actor on the body path: the integrity reservoir, the body provider, and
## the acupoints. The meridian network is core state on the Actor and reaches
## `BodyProvider` through `StatContext.meridian_network()`, so this module registers
## no component copy of it: a second, divergent source of truth for core state is
## exactly what ADR 0057 removes, and the copy made the wrong read look like a
## working one.
## BL-0951: the body's PERFECTION at departure — how far past the next gate's quality
## requirement the actor trained, against the standing realm's authored `quality_target`
## as the ceiling. The REFINEMENT axis has no headroom by design (the next gate demands
## this realm's cap at all 29 boundaries, so `Tribulation.formation_depth` reads 0.0 for
## every body departure), and the measurable axis is the acupoint quality: the denominator
## `quality_target(source) - quality_required(target)` is 0.07 at every boundary, which is
## exactly what makes deepening worth something. The shape (a clamped mean over the gate's
## own channels) mirrors the qi measure; the MEASURE is this path's own, which is
## ADR 0939 ruling 1's split.
static func departure_perfection(actor: Actor, target_id: StringName) -> float:
	if actor == null:
		return 0.0
	var state := actor.path(BodyPath.PATH_ID)
	var target := BodyRealmSeed.for_realm(target_id)
	var source := BodyRealmSeed.for_realm(state.rank_id) if state != null else null
	if target == null or source == null or target.required_meridians.is_empty():
		return 0.0
	var denominator := source.quality_target - target.quality_required
	if denominator <= 0.0:
		return 0.0
	var points := actor.component(&"acupoints") as AcupointSet
	if points == null:
		return 0.0
	var total := 0.0
	for meridian_id in target.required_meridians:
		total += _channel_quality_depth(points, meridian_id, target.quality_required, denominator)
	return total / float(target.required_meridians.size())


## The mean clamped depth of one meridian's acupoints: `(quality - gate) / denominator`,
## averaged over the points that belong to it. A meridian with no points contributes 0.0,
## which is the honest answer for a gate channel the body does not carry.
static func _channel_quality_depth(
	points: AcupointSet, meridian_id: StringName, gate: float, denominator: float
) -> float:
	var total := 0.0
	var count := 0
	for definition in AcupointDefaults.definitions():
		if definition.meridian_id != meridian_id:
			continue
		for point in points.points:
			if point.id != definition.id:
				continue
			count += 1
			if not point.blocked:
				total += clampf((point.quality - gate) / denominator, 0.0, 1.0)
	if count == 0:
		return 0.0
	return total / float(count)


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
	# The practice ledger, restored the same way the progress tracker is: a save
	# carries it as raw data because core never imports this module (ADR 0057).
	# Idempotent, because `ActorFactory.with_body_cultivation` and a save reload
	# both reach this and a body that is re-attached must keep its mastery.
	var saved_practice: Dictionary = actor.get_module_data(PRACTICE_ID)
	if not saved_practice.is_empty():
		actor.set_component(PRACTICE_ID, BodyPractice.from_dict(saved_practice))
		actor.set_module_data(PRACTICE_ID, {})
	elif actor.component(PRACTICE_ID) == null:
		actor.set_component(PRACTICE_ID, BodyPractice.new())
	var rank := _body_rank(actor)
	if rank != &"":
		# Channels must exist as soon as the module is attached. Without this the
		# network stays empty until the first cultivate(), and strengthen() then
		# rejects every meridian because it cannot find the channel.
		actor.meridians.unlock_for_realm(rank)
	# BL-0951: the tribulation prices the past realms through the carried foundation;
	# the source is injected here for the same reason the qi path injects its gate
	# kernel — `core` may not name the module that owns the record. Idempotent.
	Tribulation.set_foundation_source(Callable(FoundationApi, "tribulation_foundation"))


## The weapon/material practice ledger, or null on a body nobody attached one to.
## A null is the honest "this body has never been practised" answer, which is why
## the use loops refuse rather than minting a ledger on the spot.
##
## **PRIVATE on purpose.** This facade is at `rules.MAX_FACADE_PUBLIC_METHODS`
## (AGENTS.md), and a 13th public method fails `tools arch`. A consumer does not
## need the live object — it needs the published rows in `panel_state`, which
## carry every field a screen renders. The live ledger is a module internal, so
## the two VERBS are reached the ADR 0143 way: `app/body_practice_action.gd`
## injects them, and `ui/` names neither.
static func _practice(actor: Actor) -> BodyPractice:
	return null if actor == null else actor.component(PRACTICE_ID)


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
	if actor == null:
		return {}
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
		# **A REFUSAL A PLAYER CAN REACH IS NAMED DATA (ADR 0150).** `unavailable`
		# names why each verb cannot act, and `attempt_outcome` names what the last
		# roll became. Neither costs a facade method: this file is at
		# `rules.MAX_FACADE_PUBLIC_METHODS` and a 13th verb fails `tools arch`, which
		# is why the fix is here on the read model rather than in a new signature.
		"unavailable": _unavailable(actor, preview),
		"attempt_outcome": BodyRefusal.attempt_outcome(actor),
		# Weapon mastery and material arts, as one read. Same reason as above: the
		# two VERBS (`wield`, `reshape`) are reached through the app layer so this
		# facade does not grow a 13th method, and a screen needs the whole axis
		# published — including the kinds and arts this body may NOT yet use, because
		# "what am I missing" is the question a mastery screen exists to answer.
		"practice": _practice_state(actor),
	}


## Every weapon kind and material art, with this body's mastery on each, as
## primitives. Published whole rather than only the held rows so the panel can
## render the axis: `mastery` is 0.0 for a kind never swung, which IS the
## "high-realm novice" answer and is the fact the whole system turns on.
##
## The two lists are deliberately the same shape. A screen that wants to print
## "Six kinds. You have trained two." should not need to know there are two
## different concepts behind the two numbers.
static func _practice_state(actor: Actor) -> Dictionary:
	var ledger := _practice(actor)
	var state := actor.path(BodyPath.PATH_ID)
	var realm_id: StringName = &"" if state == null else state.rank_id
	var index := maxi(0, RealmDefaults.ladder().index_of(realm_id))
	var weapons: Array[Dictionary] = []
	for kind in WeaponKindCatalog.all():
		var mastery := 0.0 if ledger == null else ledger.mastery(kind.id)
		(
			weapons
			. append(
				{
					"id": String(kind.id),
					"name": kind.display_name,
					"demand": String(kind.demand),
					"lean": String(kind.lean),
					"counter_demands": _names(kind.counter_demands),
					"counters": String(kind.counters),
					"counter_demands_of_counter": _names(WeaponCounter.blunts(kind.counters)),
					"best_against": kind.best_against,
					"mastery": mastery,
					"uses": 0 if ledger == null else ledger.uses_of(kind.id),
					"landed": 0 if ledger == null else ledger.landed_of(kind.id),
					"available": index >= kind.min_realm_index,
				}
			)
		)
	var materials: Array[Dictionary] = []
	var parts: Array[Dictionary] = []
	for art in MaterialArtCatalog.all():
		var level := 0.0 if ledger == null else ledger.art_level(art.id)
		var owned: bool = ledger != null and ledger.has_part(art.transforms_into)
		(
			materials
			. append(
				{
					"id": String(art.id),
					"name": art.display_name,
					"material": String(art.material),
					"part": String(art.transforms_into),
					"demand": String(art.draws_demand),
					"best_against": art.best_against,
					"level": level,
					"has_part": owned,
					"cost": BodyMaterialArt.cost_of(art.id),
					"available": index >= art.min_realm_index,
				}
			)
		)
	if ledger != null:
		for key in ledger.parts.keys():
			parts.append((ledger.parts[key] as BodyPart).to_dict())
	return {
		"weapons": weapons,
		"materials": materials,
		"parts": parts,
		"material_kinds": _names(MaterialArtCatalog.materials()),
		"demands": _names(WeaponDemand.ALL),
		"blunted_yield": BodyWeaponUse.BLUNTED_YIELD,
	}


static func _names(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out


## Why each player-facing verb cannot act right now, keyed by verb, as
## `{kind, id, required, actual, label}` entries — the shape `RaceGate.unmet()`
## already produces.
##
## **KEYED BY VERB, NOT ONE FLAT LIST**, and the reason is a bug class rather than a
## preference: a screen handed a flat list has to remember to filter it, and a screen
## that forgets shows one verb's price on another verb's button — which is precisely
## the defect ADR 0150 describes, one step removed.
##
## A non-empty entry is a complaint a player can act on, and this facade spends
## nothing: `_start` already guarantees a refusal costs the actor nothing by landing
## before the pill is spent. The guarantees a consumer may rely on are stated on
## `BodyRefusal`: a `false` ALWAYS has a name here, while a name does not always
## mean the verb will refuse (the strengthen report is a union over a walk).
static func _unavailable(actor: Actor, preview: Dictionary) -> Dictionary:
	return {
		BodyRefusal.VERB_CULTIVATE: BodyRefusal.cultivate_unavailable(actor),
		BodyRefusal.VERB_RECOVER: BodyRefusal.recover_unavailable(actor),
		BodyRefusal.VERB_STRENGTHEN: BodyRefusal.strengthen_unavailable(actor),
		BodyRefusal.VERB_BREAKTHROUGH:
		BodyRefusal.breakthrough_unavailable(actor, preview.get("unmet", [])),
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
## nothing is left to train or the price is missing — which price depends on the
## channel's state, because a burn is repaired at the recovery elixir's price
## (ADR 0141) and trained at the channel elixir's.
##
## The report says which, and which candidate is which is ONE list:
## `BodyTraining.strengthen_candidates` (ADR 0150).
static func strengthen_next(actor: Actor) -> bool:
	for meridian_id in BodyTraining.strengthen_candidates(actor):
		if BodyTraining.strengthen(actor, meridian_id):
			return true
	return false


## The first half of a breakthrough: validate, spend the realm pill once, and
## commit the attempt. Returns an empty view when refused — unprepared, no target
## realm, an attempt is already in flight, or the actor's body plan forbids it.
##
## This is the durable half: the pill is spent here and the record is persisted,
## so a save taken now still resolves the same attempt on reload. The resolve is
## a separate call so the trial can span a save or a UI turn.
##
## **The body answers first (ADR 0109)**, and this call is gated for free: the
## refusal lives in `BodyAdvancement.start_attempt`, which is where the pill is
## spent. An empty view here is also what a closed path or a ceiling above the
## realm being entered looks like — the refusal costs the actor nothing, because
## it happens before any cost is paid.
##
## **No generator, BY DESIGN, and it is what makes the two halves one trial.**
## The facade takes none because the record is where the randomness lives: the
## commit draws a seed, stores it in `rng_state`, and the resolve replays that one
## number. Passing nothing here is not a gap in the interface — a second door for
## randomness into a durable decision is what let a save-spanning attempt resolve
## differently than the attempt the player committed.
static func begin_breakthrough(actor: Actor) -> Dictionary:
	var committed := BodyAdvancement.start_attempt(actor)
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
##
## The roll comes out of the record's own seed, which is why this takes no
## generator: a reload resolves the attempt the player committed rather than a new
## trial against whatever the huyệt look like now.
static func resolve_breakthrough(actor: Actor) -> bool:
	return BodyAdvancement.resolve_attempt(actor)


## Roll the breakthrough attempt in one press. A deviation is recoverable;
## re-prepare and retry. This is `begin_breakthrough` then `resolve_breakthrough`
## — the same two calls, so the one-press and the save-spanning attempt cannot
## diverge.
##
## **The body answers first (ADR 0109).** A body plan that closes the body path, or one whose
## `realm_ceiling` sits above the realm being entered, is refused BEFORE the roll. This
## facade does NOT ask `RaceGate` itself: the refusal lives in
## `BodyAdvancement.start_attempt`, which both halves of the durable lifecycle and this
## one-press call all make, so `begin_breakthrough` is gated by the same check rather
## than by a second copy of it that could fall out of step.
##
## The refusal is PUBLISHED rather than returned, and it does carry `RaceGate`'s own
## `{kind, id, required, actual, label}` entries verbatim: `panel_state`'s
## `unavailable.breakthrough` is built from `RaceGate.path_unmet` and
## `realm_ceiling_unmet` directly, so a screen quotes the same sentence the race gate
## shows anywhere else. This docstring previously claimed the RETURN carried them, which
## it never did — they reach a screen only through the read model (ADR 0150).
##
## No generator here either, for the same reason as the two halves: the commit
## draws the attempt's seed and the resolve reads it back out of the record, so a
## player's press is a real independent trial that still survives a save.
static func attempt_breakthrough(actor: Actor) -> bool:
	return BodyAdvancement.try_breakthrough(actor)


## Close the first wound a recovery item can heal: a blocked huyệt first (it
## names its own channel), then an injured channel. Consumes the realm's
## recovery item. Returns true when a repair happened, so a panel can tell a
## real recovery from a no-op.
##
## The refusal is PUBLISHED, not returned: `panel_state`'s `unavailable.recover`
## names whether there was nothing to repair or the elixir is missing, so a screen
## never has to infer it (ADR 0150). The walk itself is
## `BodyRefusal.recovery_candidates`, the same list that report asks — one
## definition, so the two cannot drift.
static func recover_next(actor: Actor) -> bool:
	for meridian_id in BodyRefusal.recovery_candidates(actor):
		if BodyTraining.recover(actor, meridian_id):
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
