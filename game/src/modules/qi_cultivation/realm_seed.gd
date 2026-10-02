class_name QiRealmSeed
extends Resource

## One destination realm's qi-cultivation contract (ADR 0011/0014/0024): the pill
## and elixir it consumes, the dantian and channel state it demands, and what a
## successful advance awards.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var training_item: StringName = &""
## Third consumable role: repairs the damage a qi deviation leaves behind — the
## dantian scar and the burned channel. A deviation must stay recoverable
## through content, not only through a lucky next roll (ADR 0031).
@export var recovery_item: StringName = &""
@export var progress_required: float = 100.0
@export var comprehension_required: float = 10.0
@export var dantian_quality_required: float = 0.5
@export var dantian_fill_required: float = 1.0
@export var dantian_tier: StringName = &"lower"
@export var required_meridians: Array[StringName] = []
@export var required_channel_state: StringName = MeridianState.OPEN
@export var channel_refinement_cap: int = 1
@export var dantian_capacity: float = 100.0
@export var rewards: Dictionary = {}


static func for_realm(realm_id: StringName) -> QiRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/qi_cultivation/realms/%s.tres" % realm_id) as QiRealmSeed
