class_name ClanState
extends RefCounted

## The versioned membership ledger, stored as a plain dictionary under
## `actor.module_data["clan_state"]` (ADR 0027 pattern). Core persists it without ever
## naming a clan.
##
## **This ledger is the single source of truth.** `actor.traits` carries `clan:` and
## `clan_rank:` mirrors for cheap reads through `StatContext.has_trait`, and the actor
## carries a `clan_summary` component for a pure provider to read. Both are derived and
## are rebuilt from here on every attach — never trusted.
##
## ## Rank is NOT derived from standing. This is the whole point.
##
## ADR 0064 makes standing and rank two independent numbers on purpose: a member can
## hold a high position on little standing, and that gap is the politics. So the
## ledger stores `standing` and `rank` as separate fields and **nothing here ever
## writes one from the other**. `ClanDef.rank_for_standing` exists to answer the
## display question ("what would this standing justify?"), and a member's stored rank
## is whatever the clan granted. Any code that recomputes `rank` from `standing` has
## deleted the feature.
##
## A member belongs to at most ONE clan. ADR 0064 makes membership singular — an actor
## may belong to no clan, and that is the normal starting state — so the ledger is a
## single record rather than a map, and `leave` is a real verb rather than a filter.
##
## ## The schema
##
## `{version, clan, rank, standing, applied}`. `applied` is what the projection last put
## on the actor: the clan and the rank whose trait mirrors are live. It is
## deliberately NOT filtered by `known_clans` — a dropped `.tres` is exactly when those
## mirrors would otherwise be stranded on the actor with nothing to take them back
## with.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"clan_state"
## Every stat modifier this module contributes is tagged with this prefix, so a
## re-projection can strip and rebuild the whole contribution from the ledger. Nothing
## is ever added under it today — a clan grants recognition, not power (ADR 0064) —
## but the namespace is what makes that a decision rather than an accident.
const SOURCE_PREFIX := "clan:"
## The `Actor.traits` mirror prefix.
const TRAIT_PREFIX := "clan:"
## Second `Actor.traits` mirror: the member's position, namespaced so it can never
## collide with the clan mirror or with a trait an unrelated module grants.
const RANK_PREFIX := "clan_rank:"


## The stat source id one clan would contribute under.
static func source_for(id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, id])


## The `Actor.traits` mirror id one clan is reflected under.
static func trait_for(id: StringName) -> StringName:
	return StringName("%s%s" % [TRAIT_PREFIX, id])


## The `Actor.traits` mirror id one position is reflected under.
static func rank_trait_for(rank: StringName) -> StringName:
	return StringName("%s%s" % [RANK_PREFIX, rank])


## True when a stat modifier source belongs to this module.
static func is_own_source(source: StringName) -> bool:
	return String(source).begins_with(SOURCE_PREFIX)


## A known-clan filter for this module. `known_clans` comes from the catalog; an entry
## naming content that no longer ships is dropped rather than persisted, so a save from
## a wider content build cannot smuggle in a clan the current build does not define.
##
## A payload that cannot be read is diagnosed as empty, never partially applied. Half a
## ledger is worse than none: the projection strips what the ledger says it applied, so
## a half-read ledger would strip the wrong mirrors and leave the rest stranded. An
## unreadable field therefore discards itself rather than poisoning the whole record —
## but an unreadable `standing` discards the whole record, because a member with an
## unreadable standing but a live rank would be a coherent-looking lie.
static func normalize(payload: Dictionary, known_clans: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"clan": "",
		"rank": "",
		"standing": 0,
		"applied": {},
	}
	if payload.is_empty():
		return out
	var clan_id := String(payload.get("clan", ""))
	if clan_id != "" and (known_clans.is_empty() or known_clans.has(clan_id)):
		out["clan"] = clan_id
		# A rank is only meaningful alongside the clan it was granted by, so it is
		# filtered by the same test. A member with no clan holds no position: this is
		# the normal state, not a gap to be filled in.
		var rank := String(payload.get("rank", ""))
		if rank != "" and out["clan"] == clan_id:
			out["rank"] = rank
	# Standing was earned INSIDE a house, so it only exists while the membership does.
	# Reading it independently would leave an actor with no clan holding the standing
	# of a house the build no longer ships — recognition with nothing recognising them,
	# and the one number a later reputation layer would read as legitimate.
	var standing = payload.get("standing", 0)
	if out["clan"] != "" and (standing is float or standing is int):
		out["standing"] = maxi(0, int(standing))
	var applied = payload.get("applied", {})
	if applied is Dictionary:
		var record := _applied_record(applied as Dictionary)
		if not record.is_empty():
			out["applied"] = record
	return out


## The empty ledger: no clan, no position, no standing. The state a fresh actor is in
## and the state `leave` returns to.
static func empty() -> Dictionary:
	return normalize({})


## The clan `ledger` names, or `&""` when it names none.
static func clan_id(ledger: Dictionary) -> StringName:
	return StringName(String(ledger.get("clan", "")))


## The position `ledger` records, or `&""`. Read from the ledger, never recomputed from
## `standing` — see the class note.
static func rank(ledger: Dictionary) -> StringName:
	return StringName(String(ledger.get("rank", "")))


## The earned standing `ledger` records. Symmetric with obligations: it can rise and it
## can fall, and nothing in this module moves it on its own.
static func standing(ledger: Dictionary) -> int:
	var value = ledger.get("standing", 0)
	return int(value) if (value is float or value is int) else 0


## Whether `ledger` records any membership at all.
static func is_member(ledger: Dictionary) -> bool:
	return clan_id(ledger) != &""


## The published floor for `clan_id` at `standing` — what the ledger would say if the
## clan derived rank from standing, which it deliberately does not. Exposed so a clan
## screen can show the gap between earned and held without a second call.
static func band_rank(clan_id: StringName, standing: int) -> StringName:
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		return &""
	return def.rank_for_standing(standing)


## `ledger` as a NEW dictionary with membership set: the clan, its entry rank, and
## `standing` clamped at zero. Rank is written here and nowhere else in the module.
##
## Passing `&""` yields the empty ledger, which is how `leave` is expressed.
static func with_membership(
	ledger: Dictionary, clan_id: StringName, standing: int = 0
) -> Dictionary:
	var out := normalize(ledger)
	if clan_id == &"":
		return empty()
	out["clan"] = String(clan_id)
	out["rank"] = String(ClanDef.new().entry_rank())
	out["standing"] = maxi(0, standing)
	return out


## `ledger` as a NEW dictionary with standing moved by `delta`, floored at zero.
## Standing can go UP and DOWN: it is earned, so it can be lost, and a module that
## could only raise it would be a favour instead of a standing.
static func with_standing(ledger: Dictionary, delta: int) -> Dictionary:
	var out := normalize(ledger)
	if not is_member(out):
		return out
	out["standing"] = maxi(0, standing(out) + delta)
	return out


## `ledger` as a NEW dictionary with the position set. The only rank writer, and it
## writes what the caller says: no cross-check against `standing`, because a member
## holding `head` on 0 standing is a legitimate character, not a bug (ADR 0064).
static func with_rank(ledger: Dictionary, rank: StringName) -> Dictionary:
	var out := normalize(ledger)
	if not is_member(out):
		return out
	if rank == &"":
		out["rank"] = ""
		return out
	var def := ClanCatalog.instance().clan_definition(clan_id(out))
	# An unknown position is refused rather than recorded: a member holding a rank the
	# clan no longer publishes would gate content against a string nothing defines.
	if def != null and not def.has_rank(rank):
		return out
	out["rank"] = String(rank)
	return out


## The record of what the projection last put on the actor: `{clan, rank}` ids.
static func applied(ledger: Dictionary) -> Dictionary:
	return ledger.get("applied", {}) as Dictionary


static func _applied_record(record: Dictionary) -> Dictionary:
	var clan_id := String(record.get("clan", ""))
	if clan_id == "":
		return {}
	var rank := String(record.get("rank", ""))
	return {"clan": clan_id, "rank": rank}
