class_name BodyRealmSeed
extends Resource

## One destination realm's preparation, awards, and training ceiling (ADR 0023).

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var strengthening_item: StringName = &""
@export var progress_required: float = 100.0
@export var physique_required: float = 10.0
@export var quality_required: float = 0.5
@export var quality_target: float = 0.5
@export var required_meridians: Array[StringName] = []
@export var required_refinement: int = 1
@export var refinement_cap: int = 1
@export var integrity_maximum: float = 100.0
@export var rewards: Dictionary = {}


static func for_realm(realm_id: StringName) -> BodyRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/body_cultivation/realms/%s.tres" % realm_id) as BodyRealmSeed
