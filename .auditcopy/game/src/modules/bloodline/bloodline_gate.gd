class_name BloodlineGate
extends RefCounted

## Evaluates authored gate requirements against an actor's bloodlines, and answers the
## two questions a lineage exists to ask: *is this awake* and *how concentrated is it*.
##
## A requirement is **data, never code**: either an empty dictionary — ungated, always
## open — or a map naming exactly one verb. No GDScript is authored per gate, so adding
## bloodline-restricted content is a content edit, not a code change.
##
## Verbs (a closed set — an unknown verb is refused, never silently true):
##   `{verb: &"is_awake",       id: &"emberblood"}`
##   `{verb: &"purity_at_least", id: &"emberblood", at: 0.6}`
##   `{verb: &"has_trait",      id: &"bloodline:emberblood"}`
##   `{verb: &"all_of",         of: [ ...requirements ]}`
##   `{verb: &"any_of",         of: [ ...requirements ]}`
##   `{verb: &"none_of",        of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of the six, refuses closed and
## names itself. Refuse-with-cause is the house rule: content that is malformed must
## fail loudly and locally, never open a door it cannot read.

## Unmet-entry kinds.
const KIND_AWAKE := &"awake"
const KIND_PURITY := &"purity"
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
		&"is_awake":
			return _is_awake(actor, requirement)
		&"purity_at_least":
			return _purity_at_least(actor, requirement)
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


## Every lineage the actor currently carries awakened, canonically ordered. The awake
## set is what gated content actually reads, so it comes from the ledger rather than
## from a stat: a stat can be item-granted, and a lineage power must not be.
static func awake(actor: Actor) -> Array[StringName]:
	return BloodlineState.awake_ids(_ledger(actor))


## The concentration `actor` carries for `lineage_id`. 0.0 for an actor that carries
## none: absence is zero concentration, not a missing key.
static func purity_of(actor: Actor, lineage_id: StringName) -> float:
	return BloodlineState.purity(_ledger(actor), lineage_id)


## Whether `lineage_id` has crossed its authored awaken threshold for `actor`.
## Refuses a lineage the catalog does not ship rather than defaulting it awake —
## content nothing defines must not gate content.
static func is_awake(actor: Actor, lineage_id: StringName) -> bool:
	if actor == null or lineage_id == &"":
		return false
	var def := BloodlineCatalog.instance().bloodline_definition(lineage_id)
	if def == null:
		return false
	return def.is_awake(purity_of(actor, lineage_id))


## Every lineage `actor` carries a concentration for, canonically ordered.
static func lineage_ids(actor: Actor) -> Array[StringName]:
	return BloodlineState.lineage_ids(_ledger(actor))


# --- Internals ---------------------------------------------------------------


static func _is_awake(actor: Actor, requirement: Dictionary) -> Dictionary:
	var lineage_id := StringName(requirement.get("id", ""))
	if lineage_id == &"":
		return _refuse("malformed", "An is_awake gate names no lineage id.")
	var def := BloodlineCatalog.instance().bloodline_definition(lineage_id)
	if def == null:
		return _refuse(
			"unknown_lineage", "The lineage '%s' is not one this build ships." % lineage_id
		)
	if is_awake(actor, lineage_id):
		return _pass()
	var purity := purity_of(actor, lineage_id)
	return _fail(
		KIND_AWAKE,
		lineage_id,
		def.awaken_threshold,
		purity,
		(
			"Requires an awakened %s line (%.2f concentrated, %.2f needed)"
			% [def.display_name, purity, def.awaken_threshold]
		)
	)


static func _purity_at_least(actor: Actor, requirement: Dictionary) -> Dictionary:
	var lineage_id := StringName(requirement.get("id", ""))
	if lineage_id == &"":
		return _refuse("malformed", "A purity_at_least gate names no lineage id.")
	var at = requirement.get("at", null)
	if not (at is float or at is int):
		return _refuse("malformed", "A purity_at_least gate needs a numeric `at`.")
	var required := clampf(float(at), 0.0, 1.0)
	var purity := purity_of(actor, lineage_id)
	if purity >= required:
		return _pass()
	return _fail(
		KIND_PURITY,
		lineage_id,
		required,
		purity,
		(
			"Requires %.2f concentration of the %s line (you carry %.2f)"
			% [required, lineage_id, purity]
		)
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
		if nested_reason == "unknown_lineage":
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


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return BloodlineState.empty()
	return BloodlineState.normalize(actor.get_module_data(BloodlineState.MODULE_KEY))


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
