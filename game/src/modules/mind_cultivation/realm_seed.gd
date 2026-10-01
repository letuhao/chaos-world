class_name MindRealmSeed
extends Resource

## One destination realm's mind-cultivation contract (ADR 0013/0016/0024): the
## pill and elixirs it consumes, the sea and channel state it demands, and what
## a successful advance awards.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var training_item: StringName = &""
@export var sea_catalyst: StringName = &""
@export var progress_required: float = 100.0
@export var comprehension_required: float = 10.0
@export var clarity_required: float = 0.5
@export var purity_required: float = 0.5
@export var sea_fill_required: float = 1.0
@export var sea_tier: StringName = &"shallow"
@export var required_meridians: Array[StringName] = []
@export var required_channel_state: StringName = MeridianState.STRENGTHENED
@export var channel_refinement_cap: int = 1
@export var sea_capacity: float = 100.0
@export var rewards: Dictionary = {}
## Work required for the Thức Hải strengthening milestone.
@export var sea_milestone_work: float = 20.0
## Work required for the meridian strengthening milestone.
@export var meridian_milestone_work: float = 15.0
## Insight required for entry.
@export var insight_required: float = 0.0
## Resonance rank required (realms 19-30).
@export var resonance_required: int = 0


static func for_realm(realm_id: StringName) -> MindRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/mind_cultivation/realms/%s.tres" % realm_id) as MindRealmSeed
