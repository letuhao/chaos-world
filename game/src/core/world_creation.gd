class_name WorldState
extends RefCounted

## World Creation (创世) — Transcendent tier (realms 28-30) ability to create
## actual worlds/realms (ADR 0019). A world has laws, layers, inhabitants,
## and ongoing upkeep. Stored on Actor.world.

# World tiers aligned to Transcendent realms
const MICRO := &"micro"
const SMALL := &"small"
const GREAT := &"great"

const STABILITY_THRESHOLD := 0.3

var tier: StringName = MICRO
var size: float = 1.0
var stability: float = 0.5
var will_strength: float = 0.5
var laws: Array[WorldLawState] = []
var layers: Array[WorldLayerState] = []
var inhabitants: Array[InhabitantRef] = []
var resources: Dictionary = {}
var upkeep_rate: float = 0.0
var time_flow_rate: float = 1.0


func _init(p_tier: StringName = MICRO, p_size: float = 1.0, p_stability: float = 0.5) -> void:
	tier = p_tier
	size = p_size
	stability = p_stability


## A world is stable at stability >= 0.3.
func is_stable() -> bool:
	return stability >= STABILITY_THRESHOLD


func add_law(law: WorldLawState) -> void:
	laws.append(law)


func get_law(law_id: StringName) -> WorldLawState:
	for law in laws:
		if law.law_id == law_id:
			return law
	return null


func add_layer(layer: WorldLayerState) -> void:
	layers.append(layer)


func add_inhabitant(inhabitant: InhabitantRef) -> void:
	inhabitants.append(inhabitant)


## Pay qi upkeep. Returns false if insufficient qi.
func pay_upkeep(qi_amount: float) -> bool:
	if qi_amount < upkeep_rate:
		return false
	return true


func to_dict() -> Dictionary:
	var laws_out: Array = []
	for law in laws:
		laws_out.append(law.to_dict())
	var layers_out: Array = []
	for layer in layers:
		layers_out.append(layer.to_dict())
	var inhabitants_out: Array = []
	for inhabitant in inhabitants:
		inhabitants_out.append(inhabitant.to_dict())
	return {
		"tier": String(tier),
		"size": size,
		"stability": stability,
		"will_strength": will_strength,
		"laws": laws_out,
		"layers": layers_out,
		"inhabitants": inhabitants_out,
		"resources": resources.duplicate(),
		"upkeep_rate": upkeep_rate,
		"time_flow_rate": time_flow_rate,
	}


static func from_dict(data: Dictionary) -> WorldState:
	var world := WorldState.new(
		StringName(data.get("tier", MICRO)),
		float(data.get("size", 1.0)),
		float(data.get("stability", 0.5))
	)
	world.will_strength = float(data.get("will_strength", 0.5))
	for law_data in data.get("laws", []):
		world.laws.append(WorldLawState.from_dict(law_data))
	for layer_data in data.get("layers", []):
		world.layers.append(WorldLayerState.from_dict(layer_data))
	for inhabitant_data in data.get("inhabitants", []):
		world.inhabitants.append(InhabitantRef.from_dict(inhabitant_data))
	world.resources = data.get("resources", {}).duplicate()
	world.upkeep_rate = float(data.get("upkeep_rate", 0.0))
	world.time_flow_rate = float(data.get("time_flow_rate", 1.0))
	return world
