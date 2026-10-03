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

## What one wave of a fight costs the body it is fought with, in dao heart. Charged
## on every descended wave, including the deciding one, so surviving has to be worth
## the waves it took (ADR 0061).
const WAVE_TOLL := 1.0

## The share of fights survived is bounded at BOTH ends and never reaches either: a
## certainty makes the fight a formality, and a coin flip makes the gate unopenable,
## which is the same defect as no gate at all. These two numbers are the ONLY copy;
## `TribulationEndurance` adds the actor's dao heart to the same slope and clamp
## (ADR 0103), so there is one answer to "how often does this actor survive".
const MIN_ENDURANCE := 0.15
const MAX_ENDURANCE := 0.85

## The largest rating `rate` can reach: the authored wave ceiling times the most
## pressured tribulation type. `endurance` spends its span across exactly this range,
## so the price term can never swallow more than the span it is drawn from.
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


## The share of fights THIS tribulation is survived at, read off its own rating and
## nothing else: no actor and no rng, so it is pure and a screen can price a fight
## before it begins. `TribulationEndurance.endurance` is the actor-aware answer and
## is the same slope and clamp with the dao heart added.
func endurance() -> float:
	return clampf(MAX_ENDURANCE - difficulty * ENDURANCE_PER_RATING, MIN_ENDURANCE, MAX_ENDURANCE)


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
	return rating * (1.0 - _preparation_reduction())


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
	measured["formation"] = _developed_share(actor)
	measured["environment"] = _arena_quality(actor)
	return measured


## How much of the bounded endurance span the recorded aid buys, capped so no
## preparation can farm the fight away.
func _preparation_reduction() -> float:
	var total := 0.0
	for aid in PREPARATION_AIDS:
		total += float(preparation.get(aid, 0.0))
	return minf(total, PREPARATION_FLOOR)


## The share of channels developed PAST merely open. A closed or merely-opened
## channel is not a formation; a body nobody trained has nothing to fight with.
func _developed_share(actor: Actor) -> float:
	var channels := actor.meridians.get_all_meridians()
	if channels.is_empty():
		return 0.0
	var developed := 0
	for channel in channels:
		if channel.state == &"expanded" or channel.state == &"strengthened":
			developed += 1
	return float(developed) / float(channels.size())


## How sound an arena the actor brings to the fight: the inside world's stability. No
## world, no arena.
func _arena_quality(actor: Actor) -> float:
	if actor.inside_world == null:
		return 0.0
	return clampf(actor.inside_world.stability, 0.0, 1.0)


## Charge one wave's toll of dao-heart strain. Floored at zero: strain cannot leave a
## hero with a negative dao heart.
func _charge_toll(actor: Actor) -> void:
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
