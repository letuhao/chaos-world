class_name Tribulation
extends RefCounted

## Heavenly Tribulation (天劫) — core infrastructure for Immortal/Transcendent
## breakthroughs (ADR 0020). Six types aligned to cultivation path and tier.
## Four phases: warning → trial → climax → aftermath.

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

# Realm threshold: Immortal tier starts at realm index 18 (earth_immortal)
const TRIBULATION_REALM_THRESHOLD := 18

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
func start(actor: Actor, p_realm_id: StringName) -> void:
	realm_id = p_realm_id
	phase = WARNING
	wave = 0
	difficulty = _compute_difficulty(actor, p_realm_id)
	max_waves = _compute_waves(p_realm_id)
	preparation = {}


## Advance to the next wave. Transitions through phases.
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


## Check if the tribulation is complete (reached aftermath).
func is_complete() -> bool:
	return phase == AFTERMATH


## Check whether this tribulation was fought for exactly `realm_id`.
## An unbound tribulation matches nothing: a legacy payload (or one never
## passed to start()) has no realm to vouch for, so it must be re-fought
## rather than silently inheriting a survivor's worth.
func matches_realm(p_realm_id: StringName) -> bool:
	return p_realm_id != &"" and realm_id == p_realm_id


## Decide the tribulation and apply it to the actor.
## On success: grants rewards (essence, blessing, insight, mark).
## On failure: applies consequences (injury, deviation, dao heart damage).
##
## The record is *kept* on the actor rather than cleared, because it is the only
## proof that this realm's fight was won. Clearing it made a survivor vanish on
## the next save, silently re-closing a gate the player had already earned.
## `Breakthrough.begin_tribulation` replaces a decided record when the next realm
## needs its own fight.
func apply_result(actor: Actor, success: bool) -> void:
	if success:
		outcome = OUTCOME_SURVIVED
		_apply_rewards(actor)
	else:
		outcome = OUTCOME_FAILED
		_apply_failure(actor)


## Whether this tribulation was fought and won. One still running, or one that
## ran to its last phase without being decided, is not a survivor.
func survived() -> bool:
	return is_complete() and outcome == OUTCOME_SURVIVED


## Get the rewards dictionary for a successful tribulation.
func get_rewards() -> Dictionary:
	return {
		"tribulation_essence": int(10 * difficulty),
		"blessing": 0.1 * difficulty,
		"insight": int(5 * difficulty),
		"mark": 1,
	}


## Serialize to dictionary.
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


## Compute difficulty from the tribulation's own type and the realm's wave count.
##
## Two authored inputs: `TYPE_PRESSURE`, above, and `_compute_waves`, which is how many
## waves this realm's tribulation drags on. Relationship debt and preparation adjust
## the result multiplicatively, below.
func _compute_difficulty(actor: Actor, p_realm_id: StringName) -> float:
	var difficulty := float(_compute_waves(p_realm_id)) * _pressure()
	# Karmic debt: negative relationships increase difficulty
	for partner_id in actor.relationships:
		var affinity: float = actor.relationships[partner_id]
		if affinity < 0.0:
			difficulty += absf(affinity) * 0.01
	# Preparation reduces difficulty. NOTE: `start()` clears `preparation` AFTER calling
	# this, so through the public API this branch only ever sees the PREVIOUS
	# tribulation's preparation. Tracked as DEF-0066; not fixed here because deciding
	# when preparation is entered is a design call, not a refactor.
	var prep_reduction := float(preparation.get("formation", 0.0))
	prep_reduction += float(preparation.get("pill", 0.0))
	prep_reduction += float(preparation.get("environment", 0.0))
	difficulty *= maxf(0.5, 1.0 - prep_reduction)
	return difficulty


## This tribulation's own pressure. An unrecognised type falls back to 1.0 rather than
## to 0.0, so a typo cannot produce a free heavenly tribulation.
func _pressure() -> float:
	return float(TYPE_PRESSURE.get(type, 1.0))


## Compute number of waves based on realm.
func _compute_waves(p_realm_id: StringName) -> int:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(p_realm_id)
	# 3-9 waves scaling with realm
	return clampi(3 + realm_index / 4, 3, 9)


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


## Apply failure consequences to the actor.
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
