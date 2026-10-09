class_name MindRealmSeed
extends Resource

## One destination realm's mind-cultivation contract (ADR 0013/0016/0024): the
## pill and elixirs it consumes, the sea and channel state it demands, and what
## a successful advance awards.

## Profiles are immutable content, so resolve each realm id once. Training and
## advancement read them on every tick; without this they would hit the
## resource loader each time.
static var _cache: Dictionary = {}

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var training_item: StringName = &""
@export var sea_catalyst: StringName = &""
## Fourth consumable role: repairs the damage a mind deviation leaves behind —
## the clouded sea and the burned channel. Every realm must author one, or a
## failed attempt is unrecoverable (ADR 0031).
@export var recovery_item: StringName = &""
@export var progress_required: float = 100.0
@export var comprehension_required: float = 10.0
@export var clarity_required: float = 0.5
@export var purity_required: float = 0.5
@export var sea_fill_required: float = 1.0
@export var sea_tier: StringName = &"shallow"
@export var required_meridians: Array[StringName] = []
@export var required_channel_state: StringName = MeridianState.STRENGTHENED
@export var channel_refinement_cap: int = 1
## BL-0951 / ADR 0939: the FOUNDATION FLOOR for entering this realm. The actor's carried
## foundation (the mean perfection of every realm it has left) must stand at or above
## this, or the breakthrough is refused by name (`foundation_insufficient`) and shown in
## the preview BEFORE the wall is hit. Authored data, never a curve.
@export var min_foundation: float = 0.0
@export var sea_capacity: float = 100.0
@export var rewards: Dictionary = {}
## Unread. `comprehension_required` above is the ENFORCED entry gate
## (`MindBreakthroughCondition`, `MindAdvancement._gates`), and this is exactly
## half of it at all 30 realms, so a weaker copy of a threshold that already binds
## can never bind itself. Delete it with the case that pins it — see BL-0146.
@export var insight_required: float = 0.0


## BL-0951's wall, as ONE predicate: the carried foundation clears this realm's authored
## floor. The condition and the preview both call THIS, so the reported gate is the
## enforced gate (ADR 0044) — the same rule `QiRealmSeed.foundation_met` follows.
func foundation_met(foundation: float) -> bool:
	return foundation >= min_foundation


static func for_realm(realm_id: StringName) -> MindRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	var cached: MindRealmSeed = _cache.get(realm_id)
	if cached != null:
		return cached
	var loaded := load("res://data/mind_cultivation/realms/%s.tres" % realm_id) as MindRealmSeed
	if loaded != null:
		_cache[realm_id] = loaded
	return loaded


## Drop cached profiles (used by content tooling and tests that regenerate data).
static func clear_cache() -> void:
	_cache.clear()
