class_name Tribulation
extends RefCounted

## Heavenly Tribulation (天劫) — core infrastructure for Immortal/Transcendent
## breakthroughs (ADR 0020). Six types aligned to cultivation path and tier.
## Four phases: warning → trial → climax → aftermath.
##
## The fight is fought here and paid once (ADR 0061): `start` prices it off the
## actor, `fight_wave` descends one wave of it and takes the verdict on the wave
## that ends it, and `apply_result` refuses to decide a record twice. A
## breakthrough consumes a survivor; it never manufactures one.

# Tribulation types
const LIGHTNING := &"lightning"
const HEART_DEMON := &"heart_demon"
const KARMIC := &"karmic"
const ELEMENTAL := &"elemental"
const SPATIAL := &"spatial"
const TEMPORAL := &"temporal"

# Phases
const WARNING := &"warning"
const TRIAL := &"trial"
const CLIMAX := &"climax"
const AFTERMATH := &"aftermath"

# Outcomes. Reaching the last phase is not surviving: a tribulation that ran to
# the end still has to be *decided*, and only a decided win opens a gate.
const OUTCOME_UNRESOLVED := &"unresolved"
const OUTCOME_SURVIVED := &"survived"
const OUTCOME_FAILED := &"failed"

## How hard each kind of heavenly tribulation is, before the realm's own wave count
## scales it. Difficulty is Tribulation's OWN rating (ADR 0050), not a read of any
## shared power scale: a challenge rating is not a stat magnitude, and pricing it off
## the realm's stat multiplier made the reward table a second balance dial nobody
## owned - and pushed the essence award toward the 9999 pool ceiling with no way to
## notice. Six authored numbers is the whole contract.
const TYPE_PRESSURE := {
	LIGHTNING: 1.0,
	HEART_DEMON: 1.2,
	KARMIC: 1.1,
	ELEMENTAL: 1.3,
	SPATIAL: 1.25,
	TEMPORAL: 1.15,
}

## What one wave of a fight costs the body it is fought with. Charged on every
## descended wave, including the deciding one, so surviving has to be worth the waves
## it took (ADR 0061). The currency is the tribulation's own: a heart-demon trial
## spends the DAO HEART, and every other trial strains COMPREHENSION — the two terms
## `TribulationEndurance` reads (BL-0932).
const WAVE_TOLL := 1.0

## The share of fights survived is bounded at BOTH ends and never reaches either: a
## certainty makes the fight a formality, and a coin flip makes the gate unopenable,
## which is the same defect as no gate at all. These two numbers are the ONLY copy,
## and the record itself does not answer the question: `TribulationEndurance` is the
## one curve that turns this rating and an actor's dao heart into a share, so a
## screen and the roll can never quote different odds (ADR 0103, ADR 0125).
const MIN_ENDURANCE := 0.15
const MAX_ENDURANCE := 0.85

## The largest rating `rate` can reach: the authored wave ceiling times the most
## pressured tribulation type. `TribulationEndurance.endurance` spends its span
## across exactly this range, so the price term can never swallow more than the span
## it is drawn from.
const RATING_SPAN := 12.0
const ENDURANCE_PER_RATING := (MAX_ENDURANCE - MIN_ENDURANCE) / RATING_SPAN

## Wave counts per REALM TIER, keyed by tier and never by ladder position: an
## inserted realm must not move every tribulation above it, which is the exact
## coupling ADR 0050 removed from `realm_power_table.tres`.
const BASE_WAVES := 3
const WAVES_BY_TIER := {
	RealmDefaults.MORTAL: BASE_WAVES,
	RealmDefaults.SPIRIT: 5,
	RealmDefaults.IMMORTAL: 7,
	RealmDefaults.TRANSCENDENT: 9,
}

## The aids `start` measures off the actor, and the ONLY ones `rate` sums. A key that
## is not named here is not read, so a caller cannot smuggle an invented discount in
## through the dictionary.
const PREPARATION_AIDS: Array[String] = ["formation", "environment"]
## The most preparation may ever buy: a fraction off the rating, never a flat
## exemption. Preparation is an input, never a gate.
const PREPARATION_FLOOR := 0.5
## The most an injected credit may MULTIPLY the measured aid by. A credit above it buys
## nothing extra: the `PREPARATION_FLOOR` cap is applied after the credit, so the ceiling on
## preparation is one number in one place and no credit can raise it.
const MAX_CREDIT := 2.0

## ## The BOND the aids are read through (BL-0830's ruling)
##
## The aids used to be a plain fraction (`formation + arena`) clamped at the floor, and for
## any legal attempt at a gated rise BOTH measured saturated: a body that may enter has
## already strengthened every required channel, so formation measured ~1.0 and the
## reduction was a flat free 0.5 — preparation was theatre. The ruled shape makes each aid
## read its own SPAN, so every point of work is marginal and an unprepared-but-legal
## attempt gets the baseline alone:
##
##     reduction = 0.2 + 0.2 * depth + 0.1 * arena        (capped at PREPARATION_FLOOR)
##
## A full record is 0.2 + 0.2 + 0.1 = 0.5 EXACTLY, and the 2:1 depth:arena ratio is the
## ruling's.
const PREPARATION_BASELINE := 0.2
const FORMATION_WEIGHT := 0.2
const ARENA_WEIGHT := 0.1
## The stability a world carries before any arena work. The arena aid reads
## `[ARENA_STABILITY_BASE, 1.0]` as `[0, 1]`, which is what makes the
## anchor-reinforcement's `+0.1` worth a real `+0.02` of the rating.
const ARENA_STABILITY_BASE := 0.5

## The kernel of the gate a body stands before: `(realm_id) -> {channels, required, cap}`,
## INJECTED by the composition root (`QiCultivationApi.attach`, which owns the seeds) for
## the same reason [member _preparation_credit] is: `core` may not name a path's content.
## An uninstalled or empty source reads as NO formation credit rather than an invented one.
static var _gate_requirement: Callable = Callable()

## ## What preparation is WORTH is injected, and `core` may not name who decides
##
## ADR 0129's `tribulation_preparation_credit` is a fraction of an authored aid, so it is
## legal to scale — but this file is `core`, and `LAYER_DEPS` holds `core` to
## `{"core", "contracts"}`, so it cannot name `difficulty`. This is the seam the repo
## already uses five times for a value a layer cannot reach (`NpcApi.set_minter`,
## `TechniqueCasting.set_resolver`, `HoldingsApi.set_store`, `WorldFact.subscribe`): a
## `static var Callable` the composition root fills, and an UNFILLED one means exactly the
## credit that was shipped before this existed.
##
## Signature `func(actor: Actor) -> float`: the credit is a per-run share, so it takes the
## body being fought for. Anything unusable is read as `1.0` (see [_credit]) — a difficulty
## that is absent, non-numeric or non-finite must be inert, never a harder fight nobody
## chose. The callable may only ever scale the aid a player MEASURED; it cannot touch the
## rating's authored inputs, the wave count, or the endurance span.
static var _preparation_credit: Callable = Callable()

var type: StringName = LIGHTNING
var phase: StringName = WARNING
var wave: int = 0
var max_waves: int = 3
var difficulty: float = 1.0
var preparation: Dictionary = {}
## The realm this tribulation was fought for. A survivor unlocks only the gate
## for the realm it was fought at, so one tribulation cannot satisfy every
## high-tier gate forever (ADR 0020, bound in ADR 0032). Empty means "unbound":
## never started, or a legacy payload saved before the binding existed.
var realm_id: StringName = &""
## Whether this tribulation has been decided, and how. Persisted, because a
## survivor that cannot survive a save would silently re-close its own gate.
var outcome: StringName = OUTCOME_UNRESOLVED


## Install the credit `[method _preparation_reduction]` spends preparation at.
## Passing an empty Callable clears it, so an uninstall is deterministic.
static func set_preparation_credit(credit: Callable) -> void:
	_preparation_credit = credit


## Install the gate-requirement kernel the formation depth reads (BL-0830). Passing an
## empty Callable clears it, so an uninstall is deterministic.
static func set_gate_requirement(source: Callable) -> void:
	_gate_requirement = source


## Whether a credit is installed, so a caller can tell "no difficulty seam" from "the seam
## says the fight is unchanged" rather than reading the same silence for both.
static func has_preparation_credit() -> bool:
	return not _preparation_credit.is_null() and _preparation_credit.is_valid()


func _init(p_type: StringName = LIGHTNING, p_max_waves: int = 3, p_difficulty: float = 1.0) -> void:
	type = p_type
	max_waves = p_max_waves
	difficulty = p_difficulty


## Start a tribulation for an actor at a given realm, binding it to that realm.
##
## Preparation is MEASURED here, before the rating is taken: the old code priced the
## fight from `preparation` and cleared it on the next line, so the aid it applied was
## always the previous fight's. `difficulty`, `max_waves` and `preparation` are all
## derived here, which is why a resumed fight must not re-derive them.
func start(actor: Actor, p_realm_id: StringName) -> void:
	realm_id = p_realm_id
	phase = WARNING
	wave = 0
	outcome = OUTCOME_UNRESOLVED
	max_waves = _compute_waves(p_realm_id)
	preparation = _measure_preparation(actor)
	difficulty = rate(actor)


## Advance to the next wave. Transitions through phases. Public because a caller may
## walk the phase machine without fighting; `fight_wave` is the verb that fights.
func advance_wave() -> void:
	if phase == WARNING:
		phase = TRIAL
		wave = 1
	elif phase == TRIAL:
		wave += 1
		if wave > max_waves:
			wave = max_waves
			phase = CLIMAX
	elif phase == CLIMAX:
		phase = AFTERMATH


## Fight ONE wave of this tribulation: charge the wave toll, descend, and on the wave
## that brings the record to its last phase roll once for the verdict. A record that
## ran to its last phase has survived nothing, so the deciding roll is taken there
## and nowhere else.
##
## THIS is the tribulation's only wave driver (ADR 0125). `advance_wave` walks the
## phase machine for a caller that is not fighting and charges nothing, and both
## production fight paths — `Breakthrough.face_tribulation` and the tribulation
## screen's `TribulationFight.fight_wave` — come through here, so a wave fought from
## a breakthrough button and a wave fought from the screen cost the same thing.
##
## `rng` makes the roll a caller's choice rather than a hope; null uses the engine's.
## The roll itself belongs to `TribulationEndurance`, the one curve in core that
## answers "did this actor survive" (ADR 0103).
func fight_wave(actor: Actor, rng: RandomNumberGenerator = null) -> void:
	if outcome != OUTCOME_UNRESOLVED:
		return
	if not is_complete():
		_charge_toll(actor)
		advance_wave()
		if not is_complete():
			return
	apply_result(actor, TribulationEndurance.survives(actor, self, rng))


## Check if the tribulation is complete (reached aftermath).
func is_complete() -> bool:
	return phase == AFTERMATH


## Check whether this tribulation was fought for exactly `realm_id`.
## An unbound tribulation matches nothing: a legacy payload (or one never
## passed to start()) has no realm to vouch for, so it must be re-fought
## rather than silently inheriting a survivor's worth.
func matches_realm(p_realm_id: StringName) -> bool:
	return p_realm_id != &"" and realm_id == p_realm_id


## Decide the tribulation and apply it to the actor, exactly once.
## On success: grants rewards (essence, blessing, insight, mark).
## On failure: applies consequences (injury, deviation, dao heart damage).
##
## Returns true when THIS call decided the fight and false when the record was
## already decided. The once-guard is the whole point: the fight paid its reward and
## then the breakthrough that consumed the survivor paid it again, so entering R19
## granted 70 insight for a 35-insight fight and stacked two `heavenly_blessing`
## statuses (ADR 0061).
##
## The record is *kept* on the actor rather than cleared, because it is the only
## proof that this realm's fight was won. `Breakthrough.begin_tribulation` replaces a
## decided record when the next realm needs its own fight.
func apply_result(actor: Actor, success: bool) -> bool:
	if outcome != OUTCOME_UNRESOLVED:
		return false
	if success:
		outcome = OUTCOME_SURVIVED
		_apply_rewards(actor)
	else:
		outcome = OUTCOME_FAILED
		_apply_failure(actor)
	return true


## Whether this tribulation was fought and won. One still running, or one that
## ran to its last phase without being decided, is not a survivor.
func survived() -> bool:
	return is_complete() and outcome == OUTCOME_SURVIVED


## What this fight is fought at, given the aid currently recorded on it. Public and
## pure: it reads the actor and `preparation` and writes neither, so a panel can ask
## what a fight costs without changing it.
##
## Two authored inputs: `TYPE_PRESSURE`, above, and `_compute_waves`, which is how
## many waves this realm's tribulation drags on. Relationship debt and preparation
## adjust the result, below.
func rate(actor: Actor) -> float:
	var rating := float(max_waves) * _pressure()
	# Karmic debt: negative relationships increase difficulty
	for partner_id in actor.relationships:
		var affinity: float = actor.relationships[partner_id]
		if affinity < 0.0:
			rating += absf(affinity) * 0.01
	return rating * (1.0 - _preparation_reduction(actor))


## Get the rewards dictionary for a successful tribulation.
func get_rewards() -> Dictionary:
	return {
		"tribulation_essence": int(10 * difficulty),
		"blessing": 0.1 * difficulty,
		"insight": int(5 * difficulty),
		"mark": 1,
	}


## Serialize to dictionary.
##
## The SINGLE serialization point. `difficulty`, `max_waves` and `preparation` are
## all derived from the tier and the actor when a fight begins, so they are written
## here as the snapshot of the price actually paid: a save between waves must resume
## the same fight, not re-derive a softer or a harsher one.
func to_dict() -> Dictionary:
	return {
		"type": String(type),
		"phase": String(phase),
		"wave": wave,
		"max_waves": max_waves,
		"difficulty": difficulty,
		"preparation": preparation.duplicate(),
		"realm_id": String(realm_id),
		"outcome": String(outcome),
	}


## Deserialize from dictionary. Payloads written before the realm binding
## existed have no "realm_id" key and load as unbound (see matches_realm).
static func from_dict(data: Dictionary) -> Tribulation:
	var tribulation := Tribulation.new(
		StringName(data.get("type", LIGHTNING)),
		int(data.get("max_waves", 3)),
		float(data.get("difficulty", 1.0))
	)
	tribulation.type = StringName(data.get("type", LIGHTNING))
	tribulation.phase = StringName(data.get("phase", WARNING))
	tribulation.wave = int(data.get("wave", 0))
	tribulation.max_waves = int(data.get("max_waves", 3))
	tribulation.difficulty = float(data.get("difficulty", 1.0))
	tribulation.preparation = data.get("preparation", {}).duplicate()
	tribulation.realm_id = StringName(data.get("realm_id", ""))
	# A payload written before outcomes existed decided nothing, so it loads
	# unresolved and must be re-decided rather than inheriting a win.
	tribulation.outcome = StringName(data.get("outcome", OUTCOME_UNRESOLVED))
	return tribulation


## This tribulation's own pressure. An unrecognised type falls back to 1.0 rather than
## to 0.0, so a typo cannot produce a free heavenly tribulation.
func _pressure() -> float:
	return float(TYPE_PRESSURE.get(type, 1.0))


## Compute number of waves from the realm id's TIER. `tier_of` answers 0 for an id the
## ladder has never heard of, and 0 is authored by nobody, so an unknown realm falls
## through to `BASE_WAVES` rather than to a position derived from a missing realm.
func _compute_waves(p_realm_id: StringName) -> int:
	var tier := RealmDefaults.ladder().tier_of(p_realm_id)
	return int(WAVES_BY_TIER.get(tier, BASE_WAVES))


## Read the aid off the actor, before the fight is rated. Every named aid is present
## even when it measures nothing, so "prepared and it did not help" and "not prepared"
## are different records rather than the same missing key.
func _measure_preparation(actor: Actor) -> Dictionary:
	var measured := {}
	for aid in PREPARATION_AIDS:
		measured[aid] = 0.0
	measured["formation"] = _formation_depth(actor)
	measured["environment"] = _arena_quality(actor)
	return measured


## How much of the bounded endurance span the recorded aids buy, capped so no
## preparation can farm the fight away. The BASELINE is what every legal attempt gets;
## each aid contributes its weight times its own measured SPAN, so deepening a channel or
## reinforcing the anchor moves the rating by a real amount at every point (BL-0830). The
## injected credit scales the measured aid only — never the baseline — and the cap is
## applied AFTER it, so a credit below one deepens the aid's discount and a credit above
## one still cannot lift preparation past `PREPARATION_FLOOR`.
func _preparation_reduction(actor: Actor) -> float:
	var aid := FORMATION_WEIGHT * float(preparation.get("formation", 0.0))
	aid += ARENA_WEIGHT * float(preparation.get("environment", 0.0))
	return minf(PREPARATION_BASELINE + aid * _credit(actor), PREPARATION_FLOOR)


## The share this body is credited for its preparation: a fraction, clamped to
## the authored window `[0, MAX_CREDIT]`. Uninstalled, invalid, non-numeric,
## out of range or non-finite all read as exactly `1.0`, because every one of those is an
## absent credit rather than a fight the player did not ask for.
func _credit(actor: Actor) -> float:
	if not has_preparation_credit():
		return 1.0
	var raw: Variant = _preparation_credit.call(actor)
	if not (raw is float or raw is int):
		return 1.0
	var credit := float(raw)
	if not is_finite(credit):
		return 1.0
	return clampf(credit, 0.0, MAX_CREDIT)


## The mean FORMATION DEPTH of the channels a gate demands, where depth is the share of
## the trainable headroom ABOVE the gate a channel has actually been pushed into:
##
##     depth = clamp((refinement - required) / (cap - required), 0, 1)
##
## averaged over the required channels. Zero at the legality floor (every channel exactly
## at its demand) and 1.0 when every required channel sits on the realm's training cap —
## which is what makes deepening past the gate worth something (BL-0830). STATIC because
## the number has a second consumer: a path snapshots it as the realm's PERFECTION at the
## moment the actor leaves (BL-0951), and a second copy of this formula is the drift
## ADR 0066 forbids. `row` is a gate requirement as the injected kernel returns it
## (`{channels, required, cap}`); an empty or degenerate row reads 0.0, the same fail-safe
## an absent aid had.
static func formation_depth(actor: Actor, row: Dictionary) -> float:
	if actor == null:
		return 0.0
	var required := int(row.get("required", 0))
	var cap := int(row.get("cap", 0))
	if cap <= required:
		# A realm whose demand IS its cap has no headroom to deepen into: the depth is
		# not measurable, so it contributes nothing rather than a division by zero.
		return 0.0
	var channels: Array = row.get("channels", [])
	if channels.is_empty():
		return 0.0
	var total := 0.0
	for meridian_id in channels:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		total += clampf(float(channel.refinement - required) / float(cap - required), 0.0, 1.0)
	return total / float(channels.size())


## The gate's own numbers arrive through the INJECTED kernel, because they live on
## another path's seeds and `core` may not read those; an uninstalled kernel or an
## unknown realm reads 0.0, the same fail-safe an absent aid had.
func _formation_depth(actor: Actor) -> float:
	if not _gate_requirement.is_valid():
		return 0.0
	var raw: Variant = _gate_requirement.call(realm_id)
	if not (raw is Dictionary):
		return 0.0
	return formation_depth(actor, raw)


## How sound an arena the actor brings to the fight: the inside world's stability over
## the span `[ARENA_STABILITY_BASE, 1.0]`, so the baseline world reads 0.0 and a fully
## reinforced one reads 1.0 — the span, not the raw number, because a raw read made the
## anchor-reinforcement's `+0.1` invisible under the floor (BL-0830). No world, no arena.
func _arena_quality(actor: Actor) -> float:
	if actor.inside_world == null:
		return 0.0
	var span := 1.0 - ARENA_STABILITY_BASE
	if span <= 0.0:
		return 0.0
	return clampf((actor.inside_world.stability - ARENA_STABILITY_BASE) / span, 0.0, 1.0)


## Charge one wave's toll. A heart-demon trial spends the DAO HEART itself — the one
## trial whose currency is the stat it is named for — through `DaoHeart.crack`, which
## floors the scar so strain cannot leave a hero with a negative heart. Every other
## trial strains COMPREHENSION at its base, floored the same way.
func _charge_toll(actor: Actor) -> void:
	if type == HEART_DEMON:
		DaoHeart.crack(actor, WAVE_TOLL)
		return
	var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	actor.stats.set_base(Stat.COMPREHENSION, maxf(0.0, comprehension - WAVE_TOLL))


## Apply success rewards to the actor.
func _apply_rewards(actor: Actor) -> void:
	var rewards := get_rewards()
	# Add tribulation essence as a resource
	var essence_pool := ResourcePool.new(&"tribulation_essence", 9999.0)
	essence_pool.current = float(rewards["tribulation_essence"])
	actor.add_resource(essence_pool)
	# Add blessing status
	var blessing := StatusEffect.new(&"heavenly_blessing", 86400.0)
	actor.add_status(blessing)
	# Boost comprehension (insight)
	var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	actor.stats.set_base(Stat.COMPREHENSION, comprehension + float(rewards["insight"]))


## Apply failure consequences to the actor. Live because `fight_wave` can lose: a
## defeat damages the body it was fought with and grants nothing.
func _apply_failure(actor: Actor) -> void:
	# Damage meridians
	for meridian in actor.meridians._meridians.values():
		actor.meridians.damage_meridian(meridian.id)
	# Damage dantian
	var dantian := actor.component(&"dantian") as Dantian
	if dantian != null:
		dantian.damage()
	# Reduce comprehension (dao heart damage)
	var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	actor.stats.set_base(Stat.COMPREHENSION, maxf(0.0, comprehension - 5.0))
