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


## Pay the anchor's reinforcement milestone: the flag, and nothing else.
##
## It also used to raise stability by 0.1. Its one reader is
## `Tribulation._arena_quality`, and `Tribulation._preparation_reduction` caps that aid
## at `PREPARATION_FLOOR` (0.5) — which a world constructed at 0.5 already reaches, so
## `minf(formation + 0.5, 0.5) == minf(formation + 0.6, 0.5)` for every input and the
## raise moved `rate()` by zero (BL-0830). `MindAnchor._inside_ok` reads stability as its
## own conjunct, so no gate lost a term either. `tests/core/test_tribulation_fight.gd`
## pins the zero.
func strengthen_anchor() -> void:
	anchor_strengthened = true


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
	world.anchor_strengthened = bool(data.get("anchor_strengthened", false))
	# A payload written before ADR 0172 still carries the retired trial key, and it
	# loads: this reader ignores a field it does not name, which is the same rule
	# `Actor.from_dict` states for every key its schema dropped. No
	# `Actor.SCHEMA_VERSION` bump either — a bump is for a slot this version GAINED
	# (ADR 0140), and refusing every existing save to protect a flag nothing could
	# act on would be worse than the loss it prevents. The key is named in ADR 0172
	# and in tests/core/test_no_anchor_trial.gd, which both assert the removal.
	return world
