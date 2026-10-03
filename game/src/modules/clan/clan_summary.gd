class_name ClanSummary
extends RefCounted

## A derived, read-only snapshot of one actor's standing inside their clan: which clan,
## which position, how much standing, and the terms that position carries.
##
## **Why this is a component rather than a catalog lookup.** `StatProvider.contribute`
## runs on every stat cache miss. If `ClanProvider` went to the catalog per term, a
## stat read would depend on mutable module state and defeat the caching `ActorStats`
## already does. So `ClanProjection` builds this once per projection and parks it on
## `actor.components`, and the provider reads only that. This mirrors how
## `RaceProjection` parks its resolved `RaceDef` and how `BloodlineProjection` parks
## its `BloodlineSummary`.

## `actor.components` slot the facade's projection attaches.
const COMPONENT := &"clan_summary"
## Alias kept so `ClanApi` reads the way `RaceApi` does. Both name one slot.
const DEF_COMPONENT := COMPONENT

## Ceiling on `patronage_tier`. The terms a clan publishes are authored data with no
## scale, so their raw sum is whatever content happens to add up to; clamping it means
## one house cannot dominate the shared stat pool and the stat stays a readable
## aggregate rather than a balance dial.
const MAX_PATRONAGE_TIER := 1.0

## The clan id, or `&""` when the actor belongs to none.
var clan_id: StringName = &""
var display_name: String = ""
## The position held, or `&""`. Stored, never derived from `standing` — ADR 0064.
var rank: StringName = &""
## The position `standing` would justify on a published reading. Equal to `rank` in an
## unpoliticised world; the gap between the two is the politics.
var band_rank: StringName = &""
## How much the member has earned, and how far they are from the next band.
var standing: int = 0
var band_count: int = 0
var band_index: int = 0
## Ordinal of `rank` in the clan's ladder, or -1 when the clan publishes none.
var rank_index: int = -1
var rank_count: int = 0
## How many rival houses the clan names.
var rivals: int = 0
## Published terms, in each direction. **Not enforced anywhere in this module.**
var patronage_terms: Array = []
var duty_terms: Array = []
## The bounded aggregate `ClanProvider` publishes as `clan_patronage_tier`.
var patronage_tier: float = 0.0
## Whether the actor belongs to a clan whose definition this build ships.
var known: bool = false


## A summary of `ledger`, resolving the clan and the published terms. An actor with no
## clan gets a well-formed empty summary rather than null, so a provider or a screen
## never has to test for absence before reading.
static func from_ledger(ledger: Dictionary) -> ClanSummary:
	var summary := ClanSummary.new()
	var state := ClanState.normalize(ledger)
	var clan_id := ClanState.clan_id(state)
	if clan_id == &"":
		return summary
	var def := ClanCatalog.instance().clan_definition(clan_id)
	summary.clan_id = clan_id
	summary.known = def != null
	summary.rank = ClanState.rank(state)
	summary.standing = ClanState.standing(state)
	summary.band_rank = def.rank_for_standing(summary.standing) if def != null else &""
	if def == null:
		return summary
	summary.display_name = def.display_name
	summary.rank_index = def.rank_index(summary.rank)
	summary.rank_count = def.ranks.size()
	summary.band_count = def.standing_bands.size()
	summary.band_index = _band_index(def, summary.standing)
	summary.rivals = def.rival_count()
	summary.patronage_terms = _sorted(def.patronage)
	summary.duty_terms = _sorted(def.duty)
	summary.patronage_tier = _tier(summary.patronage_terms, summary.duty_terms)
	return summary


## How far this member is from the next published band, or 0 at the top. A screen
## readout only; it does not move standing.
func to_next_band() -> int:
	if band_index < 0 or band_index + 1 >= band_count:
		return 0
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		return 0
	return maxi(0, int(def.standing_bands[band_index + 1]) - standing)


## Whether the member's held position is above what their standing publishes — the
## political case, made legible. False in the ordinary case where they match.
func outranks_standing() -> bool:
	if band_rank == &"" or rank == &"" or band_rank == rank:
		return false
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		return false
	return def.rank_index(rank) > def.rank_index(band_rank)


## Which published band `standing` lands in: the index of the last band whose threshold
## it reaches, or -1 when it is below the first.
static func _band_index(def: ClanDef, standing: int) -> int:
	var found := -1
	for index in def.standing_bands.size():
		if standing >= def.standing_bands[index]:
			found = index
	return found


## A bounded index of the terms this clan publishes, in both directions, and nothing
## else. Deliberately a COUNT of ordered terms rather than a sum of authored values:
## `patronage` is a free dictionary, so a sum would let one content author hand a house
## a dial nobody else can turn, while a count stays a readable "how much is on the
## table" that content cannot weaponise.
static func _tier(patronage: Array, duty: Array) -> float:
	var total := float(patronage.size() + duty.size())
	return clampf(total / 8.0, 0.0, MAX_PATRONAGE_TIER)


static func _sorted(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return keys
