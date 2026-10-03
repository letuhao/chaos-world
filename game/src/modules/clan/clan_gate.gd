class_name ClanGate
extends RefCounted

## Evaluates authored gate requirements against an actor's clan membership, and answers
## the two questions a clan exists to ask: *may this actor be admitted* and *may this
## gated content open for them*.
##
## A requirement is **data, never code**: either an empty dictionary — ungated, always
## open — or a map naming exactly one verb. No GDScript is authored per gate, so
## clan-restricted content is a content edit, not a code change.
##
## Verbs (a closed set — an unknown verb is refused, never silently true):
##   `{verb: &"is_clan",           id: &"ironpact"}`
##   `{verb: &"has_rank",          id: &"core"}`
##   `{verb: &"standing_at_least", at: 40}`
##   `{verb: &"has_trait",         id: &"clan:ironpact"}`
##   `{verb: &"all_of",            of: [ ...requirements ]}`
##   `{verb: &"any_of",            of: [ ...requirements ]}`
##   `{verb: &"none_of",           of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of the seven, refuses closed
## and names itself. Refuse-with-cause is the house rule: content that is malformed must
## fail loudly and locally, never open a door it cannot read.

## Unmet-entry kinds.
const KIND_CLAN := &"clan"
const KIND_RANK := &"rank"
const KIND_STANDING := &"standing"
const KIND_PURITY := &"purity"
const KIND_REALM := &"realm"
const KIND_BODY := &"body"
const KIND_TRAIT := &"trait"
const KIND_GATE := &"gate"


## The full verdict, always this shape:
## `{ok: bool, reason: String, unmet: Array[Dictionary]}` where every unmet entry is
## `{kind, id, required, actual, label}` — the shape `ItemRequirement.unmet()` already
## produces, so a panel renders a reason it did not have to invent.
static func evaluate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty():
		return _pass()
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse("malformed", "A gate names no verb.")
	match verb:
		&"is_clan":
			return _is_clan(actor, requirement)
		&"has_rank":
			return _has_rank(actor, requirement)
		&"standing_at_least":
			return _standing_at_least(actor, requirement)
		&"has_trait":
			return _has_trait(actor, requirement)
		&"all_of":
			return _composite(actor, requirement, true, false)
		&"any_of":
			return _composite(actor, requirement, false, false)
		&"none_of":
			return _composite(actor, requirement, false, true)
		_:
			return _refuse("unknown_verb", "Gate verb '%s' is not one this module reads." % verb)


## "May this actor be admitted to `clan_id`", as a list of complaints. Empty means the
## admission is open. The array is a list of complaints, never a count — a consumer
## asks "is this array empty" and nothing more.
##
## This gate is the ONLY place `clan` reads the two modules beneath it, and it is a
## gate over RECOGNITION rather than a grant:
##   - `min_purity` is read through `BloodlineApi.purity_of` on the clan's
##     `founding_bloodline`. Passing it recognises a lineage the member already has;
##     it never raises purity and never grants the line (ADR 0063/0064).
##   - `required_race` / `min_realm` are read through `RaceApi`, and narrow who may
##     vouch for whom. Neither changes what the body can do.
##
## An unknown clan refuses with cause rather than admitting everyone: content nothing
## defines must not gate content, and a typo'd id is a content bug.
##
## A null actor has **no opinion** and returns empty rather than a refusal: there is no
## person to admit, so this is not a statement about anyone's eligibility. `join` is the
## verb that refuses a null actor, and it does so with an `ok: false` verdict.
static func admission_unmet(actor: Actor, clan_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		out.append(
			_entry(
				KIND_CLAN,
				clan_id,
				true,
				false,
				"The clan '%s' is not one this build ships." % clan_id
			)
		)
		return out
	if def.min_purity > 0.0 and def.founding_bloodline != &"":
		var purity := BloodlineApi.purity_of(actor, def.founding_bloodline)
		if purity < def.min_purity:
			out.append(
				_entry(
					KIND_PURITY,
					def.founding_bloodline,
					def.min_purity,
					purity,
					(
						"%s admits only those already carrying the %s line at %.2f "
						% [def.display_name, def.founding_bloodline, def.min_purity]
					)
				)
			)
	if def.required_race != &"":
		var race_id := RaceApi.race_of(actor)
		if race_id != def.required_race:
			out.append(
				_entry(
					KIND_BODY,
					def.required_race,
					String(def.required_race),
					String(race_id),
					"%s recognises only the %s line" % [def.display_name, def.required_race]
				)
			)
	if def.min_realm > 0:
		var reached := _actor_realm_index(actor)
		if reached < def.min_realm:
			out.append(
				_entry(
					KIND_REALM,
					def.id,
					def.min_realm,
					reached,
					(
						"%s admits only those who have reached realm ordinal %d"
						% [def.display_name, def.min_realm]
					)
				)
			)
	return out


## The actor's clan id, or `&""`. Read from the ledger rather than the trait mirror,
## because the mirror is derived and the ledger is the truth.
static func clan_of(actor: Actor) -> StringName:
	return ClanState.clan_id(_ledger(actor))


## The position the ledger records, or `&""`. Never recomputed from standing.
static func rank_of(actor: Actor) -> StringName:
	return ClanState.rank(_ledger(actor))


## The earned standing the ledger records, or 0.
static func standing_of(actor: Actor) -> int:
	return ClanState.standing(_ledger(actor))


## Whether the actor belongs to `clan_id`. False for the empty id, so `is_clan: ""` can
## never be satisfied by an actor who is a member of something.
static func is_member_of(actor: Actor, clan_id: StringName) -> bool:
	return clan_id != &"" and clan_of(actor) == clan_id


# --- Internals ---------------------------------------------------------------


static func _is_clan(actor: Actor, requirement: Dictionary) -> Dictionary:
	var clan_id := StringName(requirement.get("id", ""))
	if clan_id == &"":
		return _refuse("malformed", "An is_clan gate names no clan id.")
	if is_member_of(actor, clan_id):
		return _pass()
	return _fail(KIND_CLAN, clan_id, true, false, "Requires membership of the clan '%s'" % clan_id)


static func _has_rank(actor: Actor, requirement: Dictionary) -> Dictionary:
	var rank := StringName(requirement.get("id", ""))
	if rank == &"":
		return _refuse("malformed", "A has_rank gate names no rank.")
	if rank_of(actor) == rank:
		return _pass()
	return _fail(
		KIND_RANK, rank, String(rank), String(rank_of(actor)), "Requires the position '%s'" % rank
	)


static func _standing_at_least(actor: Actor, requirement: Dictionary) -> Dictionary:
	var at = requirement.get("at", null)
	if not (at is float or at is int):
		return _refuse("malformed", "A standing_at_least gate needs a numeric `at`.")
	var required := maxi(0, int(at))
	var standing := standing_of(actor)
	if standing >= required:
		return _pass()
	return _fail(
		KIND_STANDING,
		clan_of(actor),
		required,
		standing,
		"Requires standing of %d (you hold %d)" % [required, standing]
	)


static func _has_trait(actor: Actor, requirement: Dictionary) -> Dictionary:
	var trait_id := StringName(requirement.get("id", ""))
	if trait_id == &"":
		return _refuse("malformed", "A has_trait gate names no trait id.")
	if actor != null and actor.traits.has(trait_id):
		return _pass()
	return _fail(KIND_TRAIT, trait_id, true, false, "Requires the trait '%s'" % trait_id)


static func _composite(
	actor: Actor, requirement: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", "A composite gate names no children.")
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		var verdict := evaluate(actor, child as Dictionary)
		if bool(verdict.get("ok", false)):
			passed += 1
			continue
		# A malformed child poisons the whole composite: refuse-with-cause means a
		# nested gate that cannot be read is never treated as satisfied.
		var nested_reason := String(verdict.get("reason", ""))
		if nested_reason == "malformed" or nested_reason == "unknown_verb":
			return verdict
		for entry in verdict.get("unmet", []) as Array:
			unmet.append(entry)
	var total := (children as Array).size()
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


## The actor's highest realm ordinal across every cultivation path, mirroring
## `RaceGate.actor_realm_index` so an admission floor never demands one specific path.
## An unstarted or unknown path counts as 0 rather than "no opinion".
static func _actor_realm_index(actor: Actor) -> int:
	if actor == null:
		return 0
	var best := 0
	for path_id in PathState.ALL:
		var state := actor.path(path_id)
		if state == null:
			continue
		best = maxi(best, maxi(0, RealmDefaults.ladder().index_of(state.rank_id)))
	return best


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return ClanState.empty()
	return ClanState.normalize(actor.get_module_data(ClanState.MODULE_KEY))


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {"ok": false, "reason": "unmet", "unmet": [_entry(kind, id, required, actual, label)]}


static func _entry(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {
		"kind": String(kind),
		"id": String(id),
		"required": required,
		"actual": actual,
		"label": label,
	}


## A refusal is distinct from a normal failure: the requirement itself is unreadable,
## which is a content bug rather than a player being told no.
static func _refuse(reason: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [_entry(KIND_GATE, &"", true, false, label)],
	}
