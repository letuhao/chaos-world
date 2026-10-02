class_name BodyRealmSeed
extends Resource

## One destination realm's preparation, awards, and training ceiling (ADR 0023).
## Expanded with full profile factors: P/C/F/T, quality/integrity targets,
## work requirements, insight floor, resonance rank, and channel training.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var strengthening_item: StringName = &""
## Third consumable role: repairs deviation damage (injured channel, blocked
## acupoint). Blockage is a recoverable overlay, so a realm must also carry the
## means to clear it — otherwise a failed attempt is unrecoverable.
@export var recovery_item: StringName = &""
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
# Work requirements (elapsed simulation time, not hardcoded real-time). This is
# the PRICE side of the cultivation loop and it is authored per realm: the rate
# that decides what one unit of work is worth is `BodyRealmProfile.rate`, and the two are
# only meaningful as a pair.
@export var work_required: float = 100.0
@export var acupoint_work: float = 20.0
@export var meridian_work: float = 15.0
# Insight floor (comprehension requirement for entry).
@export var insight_required: float = 10.0
# Resonance rank (realms 19-30 reinforce the same network).
@export var resonance_rank: int = 0
# Breakthrough risk. `chance_base` is the floor the realm offers and
# `chance_cap` its ceiling; acupoint quality buys certainty between them.
# Neither is derived from comprehension: comprehension is the entry GATE
# (insight_required), so using it for the roll made every attempt from R5 on a
# guaranteed success and left the deviation/recovery system unreachable.
@export var chance_base: float = 0.55
@export var chance_cap: float = 0.95
# Channel training after entry (channels to train while in this realm).
@export var channel_training: Array[StringName] = []


static func for_realm(realm_id: StringName) -> BodyRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/body_cultivation/realms/%s.tres" % realm_id) as BodyRealmSeed
