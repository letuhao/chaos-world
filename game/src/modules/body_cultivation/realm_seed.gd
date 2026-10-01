class_name BodyRealmSeed
extends Resource

## One destination realm's preparation, awards, and training ceiling (ADR 0023).
## Expanded with full profile factors: P/C/F/T, quality/integrity targets,
## work requirements, insight floor, resonance rank, and channel training.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var strengthening_item: StringName = &""
@export var progress_required: float = 100.0
@export var physique_required: float = 10.0
@export var quality_required: float = 0.5
@export var quality_target: float = 0.5
@export var integrity_target: float = 0.45
@export var required_meridians: Array[StringName] = []
@export var required_refinement: int = 1
@export var refinement_cap: int = 1
@export var integrity_maximum: float = 100.0
@export var rewards: Dictionary = {}
# Profile factors (ADR 0023 expansion). P is a reference power budget, never a
# stat multiplier. C scales capacity, F scales throughput, T scales technique.
@export var power_budget: float = 1.0
@export var capacity_factor: float = 1.0
@export var throughput_factor: float = 1.0
@export var technique_factor: float = 1.0
# Work requirements (elapsed simulation time, not hardcoded real-time).
@export var work_required: float = 100.0
@export var acupoint_work: float = 20.0
@export var meridian_work: float = 15.0
# Insight floor (comprehension requirement for entry).
@export var insight_required: float = 10.0
# Resonance rank (realms 19-30 reinforce the same network).
@export var resonance_rank: int = 0
# Channel training after entry (channels to train while in this realm).
@export var channel_training: Array[StringName] = []


static func for_realm(realm_id: StringName) -> BodyRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/body_cultivation/realms/%s.tres" % realm_id) as BodyRealmSeed
