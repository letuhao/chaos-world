class_name InsideWorld
extends RefCounted

## Inside World (内世界) — Immortal tier (realms 19-27) internal world that
## cultivators create within themselves (ADR 0018). Serves as storage,
## cultivation accelerator, and tactical domain.

# World tiers aligned to Immortal realms
const SEED := &"seed"
const POCKET := &"pocket"
const INNER := &"inner"

var tier: StringName = SEED
var size: float = 1.0
var stability: float = 0.5
var qi_density: float = 1.0
var time_flow: float = 1.0
var laws: Dictionary = {}
var anchor_created: bool = false
var anchor_trial_passed: bool = false
var anchor_strengthened: bool = false


func _init(
	p_tier: StringName = SEED,
	p_size: float = 1.0,
	p_stability: float = 0.5,
	p_qi_density: float = 1.0,
	p_time_flow: float = 1.0
) -> void:
	tier = p_tier
	size = p_size
	stability = p_stability
	qi_density = p_qi_density
	time_flow = p_time_flow


## A world is stable enough for storage and defense at stability >= 0.5.
func is_stable() -> bool:
	return stability >= 0.5


## Expand the world's spatial volume.
func expand_size(amount: float) -> void:
	size = maxf(0.0, size + amount)


## Improve the world's stability (clamped 0-1).
func improve_stability(amount: float) -> void:
	stability = clampf(stability + amount, 0.0, 1.0)


## Add or update a law (elemental affinity / physical rule).
func add_law(law_id: StringName, value: float) -> void:
	laws[law_id] = value


## Get a law's value (0.0 if not set).
func get_law(law_id: StringName) -> float:
	return float(laws.get(law_id, 0.0))


## Create the anchor for this world tier.
func create_anchor() -> void:
	anchor_created = true


## Mark the anchor trial as passed.
func pass_anchor_trial() -> void:
	anchor_trial_passed = true


## Strengthen the anchor's storage/stability.
func strengthen_anchor() -> void:
	anchor_strengthened = true
	improve_stability(0.1)


## Check if the anchor is ready for the next tier.
func anchor_ready() -> bool:
	return anchor_created and anchor_trial_passed and anchor_strengthened


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var laws_out := {}
	for key in laws.keys():
		laws_out[String(key)] = laws[key]
	return {
		"tier": String(tier),
		"size": size,
		"stability": stability,
		"qi_density": qi_density,
		"time_flow": time_flow,
		"laws": laws_out,
		"anchor_created": anchor_created,
		"anchor_trial_passed": anchor_trial_passed,
		"anchor_strengthened": anchor_strengthened,
	}


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> InsideWorld:
	var world := InsideWorld.new(
		StringName(data.get("tier", SEED)),
		float(data.get("size", 1.0)),
		float(data.get("stability", 0.5)),
		float(data.get("qi_density", 1.0)),
		float(data.get("time_flow", 1.0))
	)
	for key in data.get("laws", {}).keys():
		world.laws[StringName(key)] = float(data["laws"][key])
	world.anchor_created = bool(data.get("anchor_created", false))
	world.anchor_trial_passed = bool(data.get("anchor_trial_passed", false))
	world.anchor_strengthened = bool(data.get("anchor_strengthened", false))
	return world
