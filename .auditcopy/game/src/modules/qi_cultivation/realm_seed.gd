class_name QiRealmSeed
extends Resource

## One destination realm's qi-cultivation contract (ADR 0011/0014/0024): the pill
## and elixir it consumes, the dantian and channel state it demands, and what a
## successful advance awards.

## Profiles are immutable content, so resolve each realm id once. Training and
## advancement read them on every tick — `train_channel` reads one per elixir spent
## — and an uncached `load()` on each of those turned a full-ladder channel walk
## into minutes of resource loading. `MindRealmSeed` caches for the same reason.
static var _cache: Dictionary = {}

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var training_item: StringName = &""
## Third consumable role: repairs the damage a qi deviation leaves behind — the
## dantian scar and the burned channel. A deviation must stay recoverable
## through content, not only through a lucky next roll (ADR 0031).
@export var recovery_item: StringName = &""
## Two OPTIONAL catalyst roles, restored over ADR 0096's deletion (ADR 0194).
##
## Neither is a GATE. `QiBreakthroughCondition` reads progress, comprehension,
## quality, fill, the pill and the channels — never a catalyst — so nothing here
## can make a realm unreachable, which is exactly the objection ADR 0096 raised
## and the reason it deleted the family. Both buy headroom past a gate:
##
## - `dantian_catalyst` is the PRICE of a `cultivate` sitting whose circulation
##   overflows the reservoir, and the overflow becomes quality past the next
##   realm's own floor — roll certainty the free verb cannot reach, because
##   `cultivate` stops refining at that floor.
## - `meridian_catalyst` pays for one step on a channel the next realm's gate
##   does NOT name, which no gate asks for and no elixir is spent on.
##
## `QiTraining.cultivate` and `QiTraining.train_off_gate_channel` are the only
## two readers; `tools/cultivation/audit.py` fails a catalyst that no gate
## refuses AND a catalyst no verb consumes.
@export var dantian_catalyst: StringName = &""
@export var meridian_catalyst: StringName = &""
@export var progress_required: float = 100.0
@export var comprehension_required: float = 10.0
@export var dantian_quality_required: float = 0.5
@export var dantian_fill_required: float = 1.0
@export var required_meridians: Array[StringName] = []
@export var required_channel_state: StringName = MeridianState.OPEN
## Training depth each required channel must carry to enter this realm, counted on
## a channel already at `required_channel_state`. The same gate/ceiling pair the
## body path authors (`BodyRealmSeed.required_refinement` / `refinement_cap`):
## a realm's demand never exceeds the cap the realm below it offered, so one
## realm of elixirs reaches it and no elixir count falls short (ADR 0095).
## Without this the ladder's whole channel ladder was unreachable — all 30 seeds
## demanded `open`, so `expand`, `strengthen` and `refine` were never required and
## `channel_refinement_cap` was read by nothing but a branch that could not run.
@export var required_channel_refinement: int = 0
## The deepest a required channel may be trained while standing in THIS realm.
@export var channel_refinement_cap: int = 1
@export var dantian_capacity: float = 100.0
@export var rewards: Dictionary = {}


static func for_realm(realm_id: StringName) -> QiRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	var cached: QiRealmSeed = _cache.get(realm_id)
	if cached != null:
		return cached
	var loaded := load("res://data/qi_cultivation/realms/%s.tres" % realm_id) as QiRealmSeed
	if loaded != null:
		_cache[realm_id] = loaded
	return loaded


## Drop cached profiles. Content tooling and tests that regenerate the realm seeds
## need it, or a suite would keep measuring against a stale profile.
static func clear_cache() -> void:
	_cache.clear()


## Whether one channel satisfies this realm's channel gate: uninjured, at least
## `required_channel_state`, and refined to `required_channel_refinement`.
##
## The one definition of that gate. `QiBreakthroughCondition` enforces it and both
## previews report it, so a preview cannot disagree with the action it previews
## (ADR 0044) — the defect ADR 0036 recorded as still open, when `advancement.gd`
## and `breakthrough_transaction.gd` each carried their own copy.
func channel_met(channel: MeridianState) -> bool:
	if channel == null or not channel.meets(required_channel_state):
		return false
	return channel.refinement >= required_channel_refinement
