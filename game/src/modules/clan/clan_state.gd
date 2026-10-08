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
## The ceiling a clan standing is measured against when its def authors none.
##
## **AN ALIAS of `InstitutionClaim.DEFAULT_STANDING_CAP`, which now owns the one
## number** (DEF-0339). It used to be the fourth bare `100` in the tree; the
## other three (`InstitutionClaim.from_dict`, `InstitutionLedger.read`,
## `InstitutionFounding._standing_cap`) alias the same constant, so a retune is
## one edit. This name is kept because a clan reader asks a clan question.
const DEFAULT_STANDING_CAP := InstitutionClaim.DEFAULT_STANDING_CAP


## The stat source id one clan would contribute under.
static func source_for(id: StringName) -> StringName:
	return InstitutionLedger.source_tagged(SOURCE_PREFIX, id)


## The `Actor.traits` mirror id one clan is reflected under.
static func trait_for(id: StringName) -> StringName:
	return InstitutionLedger.source_tagged(TRAIT_PREFIX, id)


## The `Actor.traits` mirror id one position is reflected under.
static func rank_trait_for(rank: StringName) -> StringName:
	return InstitutionLedger.source_tagged(RANK_PREFIX, rank)


## True when a stat modifier source belongs to this module. **A delegate**: the SHAPE is
## shared and the NAMESPACE is not — `InstitutionLedger.owns_source` takes the prefix as an
## argument precisely so a `sect:` modifier can never satisfy a clan's strip half, which is
## the bug the prefix exists to prevent (ADR 0271 decision 3).
static func is_own_source(source: StringName) -> bool:
	return InstitutionLedger.owns_source(SOURCE_PREFIX, source)


## A known-clan filter for this module. `known_clans` comes from the catalog; an entry
## naming content that no longer ships is dropped rather than persisted, so a save from
## a wider content build cannot smuggle in a clan the current build does not define.
##
## A payload that cannot be read is diagnosed as empty, never partially applied.
## Half a ledger is worse than none: the projection strips what the ledger says it
## applied, so a half-read ledger would strip the wrong mirrors and leave the rest
## stranded.
##
## So a **wrong-typed id field discards the WHOLE record** rather than just itself —
## `clan`, `rank`, or an id inside `applied`. The docstring's "an unreadable field
## discards itself" is the weaker rule and is what shipped: `{"clan": "t_house",
## "rank": 17}` kept the membership and dropped only the rank, which reads as a
## member who holds a house but no post — a plausible lie the caller cannot detect.
## An absent field is different and normal: a member who holds no rank simply has
## none, and that is not corruption.
##
## **Every id arrives through `_text`, never a raw `String(...)` cast** — see that
## helper for why the cast is the wrong tool on a save payload.
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
	# An ABSENT field is normal. A present field of the wrong TYPE is corruption, and
	# `_text` cannot tell the two apart on its own — so each is checked here, and a
	# hit discards the record rather than coercing a guess out of the bytes.
	for key in ["clan", "rank"]:
		if payload.has(key) and not _is_text(payload[key]):
			return empty()
	var applied = payload.get("applied", {})
	if payload.has("applied") and not (applied is Dictionary):
		return empty()
	var clan_id := _text(payload.get("clan", ""), "")
	if clan_id != "" and (known_clans.is_empty() or known_clans.has(clan_id)):
		out["clan"] = clan_id
		# A rank is only meaningful alongside the clan it was granted by, so it is
		# filtered by the same test. A member with no clan holds no position: this is
		# the normal state, not a gap to be filled in.
		var rank := _text(payload.get("rank", ""), "")
		if rank != "" and out["clan"] == clan_id:
			out["rank"] = rank
	# Standing was earned INSIDE a house, so it only exists while the membership does.
	# Reading it independently would leave an actor with no clan holding the standing
	# of a house the build no longer ships — recognition with nothing recognising them.
	var standing = payload.get("standing", 0)
	if out["clan"] != "":
		if not (standing is float or standing is int):
			return empty()
		out["standing"] = maxi(0, int(standing))
	if applied is Dictionary:
		if _applied_corrupt(applied as Dictionary):
			# Same rule as the fields above, one level down: an `applied` record
			# holding a wrong-typed id means the projection's own bookkeeping is
			# damaged, and a membership built on top of it would strip the wrong
			# mirrors. `{}` for the record is indistinguishable from "applied
			# nothing", so the record itself must be the thing that refuses.
			return empty()
		var record := _applied_record(applied as Dictionary)
		if not record.is_empty():
			out["applied"] = record
	return out


## Whether `record` holds a wrong-typed id, as opposed to merely naming none. An
## absent id is a projection that applied nothing; a wrong-typed one is damage.
static func _applied_corrupt(record: Dictionary) -> bool:
	for key in ["clan", "rank"]:
		if record.has(key) and not _is_text(record[key]):
			return true
	return false


## Whether `value` is genuinely text — a `String` or a `StringName`. Paired with
## `_text`, which CONVERTS the same question; this one only ASKS it, so `normalize` can
## tell a corrupt field from an absent one. **A delegate, for the reason `_text` is one**:
## `InstitutionLedger.is_text` is the ASK half and was written for exactly this caller, so
## keeping a body here is the second copy the ratchet measures — the type test and the
## fallback are two halves of ONE decision and are read together or not at all.
static func _is_text(value: Variant) -> bool:
	return InstitutionLedger.is_text(value)


## The empty ledger: no clan, no position, no standing. The state a fresh actor is in
## and the state `leave` returns to.
static func empty() -> Dictionary:
	return normalize({})


## The clan `ledger` names, or `&""` when it names none.
##
## Through `_text`, never a raw `String(...)` cast: `String(42.0)` RAISES in
## GDScript rather than yielding `"42.0"`, so a corrupt save would abort `attach`
## instead of reading as the unaffiliated member it actually is. That is the whole
## reason `_text` exists — see its own note below.
static func clan_id(ledger: Dictionary) -> StringName:
	return StringName(_text(ledger.get("clan", ""), ""))


## The position `ledger` records, or `&""`. Read from the ledger, never recomputed from
## `standing` — see the class note. Through `_text` for the same reason as `clan_id`.
static func rank(ledger: Dictionary) -> StringName:
	return StringName(_text(ledger.get("rank", ""), ""))


## The earned standing `ledger` records. Symmetric with obligations: it can rise and it
## can fall, and nothing in this module moves it on its own.
##
## **Not clamped into `ClanDef.standing_cap`, deliberately.** `SectState.standing` clamps
## because a sect's ledger is a CLAIM and a claim's standing is bounded by its own cap
## (`InstitutionClaim.move_standing` clamps the same way). A clan's ledger is not a claim
## today — it is five keys on its own vocabulary — so clamping here would be a second,
## unshared rule. Measured, not assumed: `test_clan_grants_no_power.gd` raises standing by
## 10,000 and asserts `ClanStats.STANDING` reads 10000, and
## `test_clan_standing_and_rank.gd` raises a member to 500 to publish them as sitting BELOW
## what their standing reads as. A clamp would truncate both, and the second is ADR 0064's
## politics: earning far past every published rung is a legitimate character, not a data
## error. The cap bounds the RATIO ([method claim]), never this number.
static func standing(ledger: Dictionary) -> int:
	var value = ledger.get("standing", 0)
	return int(value) if (value is float or value is int) else 0


## The ceiling a claim built from `ledger` clamps against: the clan def's authored
## `standing_cap`, REPAIRED to at least 1.
##
## **The repair is the point.** A cap that cannot be computed makes `normalized()` answer
## `0.0` — `InstitutionClaim.normalized` returns 0 for `standing_cap <= 0` — which reads as
## a member nobody respects. So a def authoring zero or a negative is floored here rather
## than persisted, which is the same repair `InstitutionClaim.from_dict`,
## `InstitutionLedger.read` and `SectState.normalize` all perform.
##
## A clan no def names falls back to `InstitutionClaim`'s own authored default rather than
## to 0, for the same reason: **absence is not a broken cap**, it is a house this build no
## longer ships, and it must still produce a computable ratio instead of a member who reads
## as universally despised.
static func standing_cap(clan_id: StringName) -> int:
	if clan_id == &"":
		return DEFAULT_STANDING_CAP
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		return DEFAULT_STANDING_CAP
	return maxi(1, def.standing_cap)


## `ledger` as the shared claim every institution speaks (ADR 0083): `rank` is the
## position, `standing` the earned number, and the ceiling is this clan's own authored cap
## rather than the shared default.
##
## **A DELEGATE to `InstitutionClaim.from_dict`, never a second shape.** One vocabulary
## means `clan`, `sect` and `nation` answer "how does this read as a claim" the same way,
## and a divergent copy is the ADR 0066 failure mode in a new place — the same reasoning
## `SectState.claim` records. Two keys are translated rather than renamed in the save:
## the ledger spells its position `rank` and its membership `clan`, and renaming either in
## `normalize` would be a save-schema break for a read.
##
## `obligation` is carried as `{}` and that is the one honest difference from sect, not an
## omission: a clan's `patronage` and `duty` are authored PROSE (`"A reduced stipend is
## owed to a member the house can no longer call on."`), and `InstitutionLedger.
## positive_lines` keeps only strictly positive INTEGERS — every one of those lines would be
## dropped, so an `obligation` map here would persist empty and then read as "this member
## owes nothing" on a house that publishes terms. Clan's terms become enforceable when the
## social layer lands and they become period COUNTS; until then there is nothing to owe in
## periods, and the map is deferred rather than faked.
static func claim(ledger: Dictionary) -> InstitutionClaim:
	var state := normalize(ledger)
	var data := {
		"position": String(rank(state)),
		"standing": standing(state),
		"standing_cap": standing_cap(clan_id(state)),
		"obligation": {},
	}
	return InstitutionClaim.from_dict(data)


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


# --- Internals ---------------------------------------------------------------


## `value` when it really is text (a `String` or a `StringName`), otherwise `fallback`.
## **A DELEGATE, and the copy that used to live here is deleted** (ADR 0271 decision 3).
##
## This file documented itself as "`sect_state.gd`'s `_text`, carried over unchanged", so
## the pair was one rule written twice and kept in step by hand — the `RealmRate` shape
## ADR 0066 exists to end. `InstitutionLedger.text` owns the coercion and the reasoning
## (`String(42.0)` RAISES in GDScript rather than yielding `"42.0"`, so a raw cast on a
## save payload aborts `attach` instead of reading a corrupt field as absent — the exact
## opposite of the rule `normalize` above is written to enforce). Call sites still say
## `_text` because this is the hot path of every attach; what matters is that there is
## no body here that could drift.
static func _text(value: Variant, fallback: String) -> String:
	return InstitutionLedger.text(value, fallback)


## The projection's record of what it last applied, read back so a rebuild can
## strip exactly that and nothing else.
##
## **A wrong-typed id inside `applied` discards the whole record**, by the same rule
## as the top-level fields: `_text` falls back to `""`, and a record that quietly
## becomes half-empty is worse than none, because the caller cannot tell "this
## projection applied nothing" from "this record was corrupt" — and the first is
## true while the second is what happened. Returning `{}` for both is the honest
## answer only if `normalize` also refuses, which it does.
static func _applied_record(record: Dictionary) -> Dictionary:
	for key in ["clan", "rank"]:
		if record.has(key) and not _is_text(record[key]):
			return {}
	var clan_id := _text(record.get("clan", ""), "")
	if clan_id == "":
		return {}
	var rank := _text(record.get("rank", ""), "")
	return {"clan": clan_id, "rank": rank}
