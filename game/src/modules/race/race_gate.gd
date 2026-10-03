class_name RaceGate
extends RefCounted

## Evaluates authored gate requirements against an actor's body plan, and answers the
## two structural questions a race exists to ask: *can this body take this path at all*
## and *what realm can this body never pass*.
##
## A requirement is **data, never code**: either an empty dictionary — ungated, always
## open — or a map naming exactly one verb. No GDScript is authored per gate, so adding
## race-restricted content is a content edit, not a code change.
##
## Verbs (a closed set — an unknown verb is refused, never silently true):
##   `{verb: &"is_race",         id: &"stoneborn"}`
##   `{verb: &"race_allows_path", id: &"mind_cultivation"}`
##   `{verb: &"has_trait",       id: &"race:stoneborn"}`
##   `{verb: &"realm_ceiling",   at: 12}` — the actor is at or below that ordinal
##   `{verb: &"all_of",          of: [ ...requirements ]}`
##   `{verb: &"any_of",          of: [ ...requirements ]}`
##   `{verb: &"none_of",         of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of the seven, refuses closed
## and names itself. Refuse-with-cause is the house rule: content that is malformed must
## fail loudly and locally, never open a door it cannot read.

## Unmet-entry kinds.
const KIND_RACE := &"race"
const KIND_PATH := &"path"
const KIND_TRAIT := &"trait"
const KIND_REALM := &"realm_ceiling"
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
		&"is_race":
			return _is_race(actor, requirement)
		&"race_allows_path":
			return _race_allows_path(actor, requirement)
		&"has_trait":
			return _has_trait(actor, requirement)
		&"realm_ceiling":
			return _realm_ceiling(actor, requirement)
		&"all_of":
			return _composite(actor, requirement, true, false)
		&"any_of":
			return _composite(actor, requirement, false, false)
		&"none_of":
			return _composite(actor, requirement, false, true)
		_:
			return _refuse("unknown_verb", "Gate verb '%s' is not one this module reads." % verb)


## "This body cannot take this path" as `{kind, id, required, actual, label}` entries.
## Empty means the body CAN take it — the array is a list of complaints, never a count.
##
## An actor with no race takes no path restriction: no body plan has been authored for it
## yet, and inventing a ceiling for it would gate content on a content gap.
static func path_unmet(actor: Actor, path_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def := _def(actor)
	if def == null or path_id == &"":
		return out
	if def.allows_path(path_id):
		return out
	(
		out
		. append(
			{
				"kind": String(KIND_PATH),
				"id": String(path_id),
				"required": true,
				"actual": false,
				"label": "The %s body cannot cultivate %s" % [def.display_name, path_id],
			}
		)
	)
	return out


## Whether `actor` may cultivate `path_id` at all.
static func allows_path(actor: Actor, path_id: StringName) -> bool:
	return path_unmet(actor, path_id).is_empty()


## "This body stops at realm N" as one `{kind, id, required, actual, label}` entry, or
## an empty array when the body has no ceiling, has not reached it, or has no race.
## An empty array is the answer at and below the ceiling too, so a consumer asks
## "is this array empty" and never has to know the ceiling's own semantics.
static func realm_ceiling_unmet(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def := _def(actor)
	if def == null or def.realm_ceiling <= 0:
		return out
	var reached := actor_realm_index(actor)
	if reached <= def.realm_ceiling:
		return out
	(
		out
		. append(
			{
				"kind": String(KIND_REALM),
				"id": String(def.id),
				"required": def.realm_ceiling,
				"actual": reached,
				"label":
				(
					"The %s body stops at realm %d (you are at %d)"
					% [def.display_name, def.realm_ceiling, reached]
				),
			}
		)
	)
	return out


## The actor's highest realm ordinal across every cultivation path it has, so a ceiling
## never demands one specific path. `PathState.ALL` keeps this from naming a module, and
## `RealmDefaults.ladder()` is the shared ladder every system already reads.
##
## An unstarted or unknown path counts as ordinal 0 rather than "no opinion": a ceiling
## must not be satisfied by an actor whose rank cannot be read.
static func actor_realm_index(actor: Actor) -> int:
	var best := 0
	for path_id in PathState.ALL:
		var state := actor.path(path_id)
		if state == null:
			continue
		best = maxi(best, maxi(0, RealmDefaults.ladder().index_of(state.rank_id)))
	return best


## Every cultivation path this body cannot take, canonically ordered.
static func closed_paths(actor: Actor) -> Array[StringName]:
	var def := _def(actor)
	if def == null:
		return []
	var out: Array[StringName] = []
	for path_id in def.closed_paths:
		if not out.has(path_id):
			out.append(path_id)
	out.sort()
	return out


# --- Internals ---------------------------------------------------------------


static func _is_race(actor: Actor, requirement: Dictionary) -> Dictionary:
	var race_id := StringName(requirement.get("id", ""))
	if race_id == &"":
		return _refuse("malformed", "An is_race gate names no race id.")
	var held := race_of(actor) == race_id
	if held:
		return _pass()
	return _fail(KIND_RACE, race_id, true, false, "Requires the race '%s'" % race_id)


static func _race_allows_path(actor: Actor, requirement: Dictionary) -> Dictionary:
	var path_id := StringName(requirement.get("id", ""))
	if path_id == &"":
		return _refuse("malformed", "A race_allows_path gate names no path id.")
	var unmet := path_unmet(actor, path_id)
	if unmet.is_empty():
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


static func _has_trait(actor: Actor, requirement: Dictionary) -> Dictionary:
	var trait_id := StringName(requirement.get("id", ""))
	if trait_id == &"":
		return _refuse("malformed", "A has_trait gate names no trait id.")
	if actor != null and actor.traits.has(trait_id):
		return _pass()
	return _fail(KIND_TRAIT, trait_id, true, false, "Requires the trait '%s'" % trait_id)


static func _realm_ceiling(actor: Actor, requirement: Dictionary) -> Dictionary:
	var at := int(requirement.get("at", 0))
	if at < 0:
		return _refuse("malformed", "A realm_ceiling gate needs a non-negative `at`.")
	var unmet := realm_ceiling_unmet(actor)
	if unmet.is_empty():
		return _pass()
	var entry := (unmet[0] as Dictionary).duplicate()
	entry["required"] = at
	entry["label"] = "Requires a body that reaches realm %d" % at
	return {"ok": false, "reason": "unmet", "unmet": [entry]}


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


## The actor's race id, read from the ledger rather than the trait mirror, because the
## mirror is derived and the ledger is the truth.
static func race_of(actor: Actor) -> StringName:
	if actor == null:
		return &""
	return RaceState.race_id(RaceState.normalize(actor.get_module_data(RaceState.MODULE_KEY)))


static func _def(actor: Actor) -> RaceDef:
	if actor == null:
		return null
	var known := actor.component(RaceProjection.DEF_COMPONENT) as RaceDef
	if known != null:
		return known
	# Fallback for an actor attached before this module existed: the ledger still names
	# the race, so the definition is one catalog read away. Never a guess.
	return RaceCatalog.instance().race_definition(RaceState.race_id(_ledger(actor)))


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return RaceState.empty()
	return RaceState.normalize(actor.get_module_data(RaceState.MODULE_KEY))


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": "unmet",
		"unmet":
		[
			{
				"kind": String(kind),
				"id": String(id),
				"required": required,
				"actual": actual,
				"label": label
			}
		],
	}


## A refusal is distinct from a normal failure: the requirement itself is unreadable,
## which is a content bug rather than a player being told no.
static func _refuse(reason: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet":
		[{"kind": String(KIND_GATE), "id": "", "required": true, "actual": false, "label": label}],
	}
