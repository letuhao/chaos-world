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

# Realm threshold: Immortal tier starts at realm index 18 (earth_immortal)
const TRIBULATION_REALM_THRESHOLD := 18

var type: StringName = LIGHTNING
var phase: StringName = WARNING
var wave: int = 0
var max_waves: int = 3
var difficulty: float = 1.0
var preparation: Dictionary = {}


func _init(p_type: StringName = LIGHTNING, p_max_waves: int = 3, p_difficulty: float = 1.0) -> void:
	type = p_type
	max_waves = p_max_waves
	difficulty = p_difficulty


## Start a tribulation for an actor at a given realm.
func start(actor: Actor, realm_id: StringName) -> void:
	phase = WARNING
	wave = 0
	difficulty = _compute_difficulty(actor, realm_id)
	max_waves = _compute_waves(realm_id)
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


## Apply the result of the tribulation to the actor.
## On success: grants rewards (essence, blessing, insight, mark).
## On failure: applies consequences (injury, deviation, dao heart damage).
func apply_result(actor: Actor, success: bool) -> void:
	if success:
		_apply_rewards(actor)
	else:
		_apply_failure(actor)
	actor.tribulation = null


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
	}


## Deserialize from dictionary.
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
	return tribulation


## Compute difficulty based on realm and actor state.
func _compute_difficulty(actor: Actor, realm_id: StringName) -> float:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(realm_id)
	var base_difficulty := 1.0 + realm_index * 0.15
	# Karmic debt: negative relationships increase difficulty
	for partner_id in actor.relationships:
		var affinity: float = actor.relationships[partner_id]
		if affinity < 0.0:
			base_difficulty += absf(affinity) * 0.01
	# Preparation reduces difficulty
	var prep_reduction := float(preparation.get("formation", 0.0))
	prep_reduction += float(preparation.get("pill", 0.0))
	prep_reduction += float(preparation.get("environment", 0.0))
	base_difficulty *= maxf(0.5, 1.0 - prep_reduction)
	return base_difficulty


## Compute number of waves based on realm.
func _compute_waves(realm_id: StringName) -> int:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(realm_id)
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
