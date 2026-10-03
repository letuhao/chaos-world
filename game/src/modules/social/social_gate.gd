class_name SocialGate
extends RefCounted

## Evaluates an authored social requirement against the ledger (ADR 0076).
##
## **A gate reads the ledger, never a derived stat.** A stat can be satisfied by an item
## or a pill, so a gate that reads one is a gate the player can buy — which is exactly how
## "friendship" becomes a shop discount a grinder unlocks instead of a relationship. This
## is the same rule the race gate already holds to (ADR 0062).
##
## The requirement is a plain `Dictionary`, never a `Resource`, so it serializes inside a
## quest or a placement without a contracts-layer value object (ADR 0076).

const VERB_BOND_AT_LEAST := &"bond_at_least"
const VERB_TRUST_AT_LEAST := &"trust_at_least"
const VERB_STANDING_AT_LEAST := &"standing_at_least"
const VERB_REGARD_AT_LEAST := &"regard_at_least"
const VERB_CAUSED_BY := &"caused_by"
const VERB_ALL_OF := &"all_of"
const VERB_ANY_OF := &"any_of"
const VERB_NONE_OF := &"none_of"

const VERBS: Array[StringName] = [
	VERB_BOND_AT_LEAST,
	VERB_TRUST_AT_LEAST,
	VERB_STANDING_AT_LEAST,
	VERB_REGARD_AT_LEAST,
	VERB_CAUSED_BY,
	VERB_ALL_OF,
	VERB_ANY_OF,
	VERB_NONE_OF,
]


## `{ok: bool, reason: String, unmet: Array[Dictionary]}`. An empty requirement is
## ungated and always open. An unknown verb refuses closed and names itself, so a typo in
## authored content fails loudly instead of quietly unlocking content.
static func evaluate(state: SocialState, requirement: Dictionary) -> Dictionary:
	if state == null:
		return _refuse("no_social_state")
	if requirement.is_empty():
		return {"ok": true, "reason": "", "unmet": []}
	var verb := StringName(requirement.get("verb", ""))
	match verb:
		VERB_BOND_AT_LEAST:
			return _bond_at_least(state, requirement)
		VERB_TRUST_AT_LEAST:
			return _axis_at_least(state, requirement, &"trust")
		VERB_STANDING_AT_LEAST:
			return _axis_at_least(state, requirement, &"standing")
		VERB_REGARD_AT_LEAST:
			return _regard_at_least(state, requirement)
		VERB_CAUSED_BY:
			return _caused_by(state, requirement)
		VERB_ALL_OF:
			return _aggregate(state, requirement, VERB_ALL_OF, true, false)
		VERB_ANY_OF:
			return _aggregate(state, requirement, VERB_ANY_OF, false, true)
		VERB_NONE_OF:
			return _aggregate(state, requirement, VERB_NONE_OF, true, true)
	return {
		"ok": false,
		"reason": "unknown_verb",
		"unmet":
		[{"kind": "verb", "id": String(verb), "required": "a_known_verb", "label": String(verb)}],
	}


static func _bond_at_least(state: SocialState, requirement: Dictionary) -> Dictionary:
	var partner_id := StringName(requirement.get("partner", ""))
	var need := StringName(requirement.get("at_least", SocialBondClass.FRIEND))
	var bond := state.bond(partner_id)
	var actual := SocialBondClass.STRANGER if bond == null else bond.bond_class()
	if SocialBondClass.at_least(actual, need):
		return _pass()
	return _fail(
		"bond_at_least",
		String(partner_id),
		SocialBondClass.label(need),
		SocialBondClass.label(actual)
	)


static func _axis_at_least(
	state: SocialState, requirement: Dictionary, axis: StringName
) -> Dictionary:
	var partner_id := StringName(requirement.get("partner", ""))
	var need := float(requirement.get("at_least", 0.0))
	var bond := state.bond(partner_id)
	var actual := 0.0
	if bond != null:
		actual = bond.standing if axis == &"standing" else bond.trust
	if actual >= need:
		return _pass()
	return _fail(axis, String(partner_id), str(need), str(actual))


## ## `regard_at_least` is why `regard` is not write-only
##
## Every other verb reads a `SocialBond`, so before BL-0200 the institutional read
## model had no question anyone could ask of it: an author could not gate content on
## "the sect thinks well of you" even once something wrote the number. This verb is
## the reader, and it reads the PROJECTED `regard` rather than a bond's raw standing,
## so a gate and a panel cannot disagree about the same question.
##
## A partner with no institutional bond is `0.0`, which is the honest reading rather
## than a special case: the actor is not regarded by an institution they have never
## sworn to, served or been cast out of.
static func _regard_at_least(state: SocialState, requirement: Dictionary) -> Dictionary:
	var partner_id := String(requirement.get("partner", ""))
	var need := float(requirement.get("at_least", 0.0))
	var actual := float(state.regard.get(partner_id, 0.0))
	if actual >= need:
		return _pass()
	return _fail(VERB_REGARD_AT_LEAST, partner_id, str(need), str(actual))


static func _caused_by(state: SocialState, requirement: Dictionary) -> Dictionary:
	var partner_id := StringName(requirement.get("partner", ""))
	var need := StringName(requirement.get("cause", ""))
	var bond := state.bond(partner_id)
	if bond != null and bond.causes.has(String(need)):
		return _pass()
	return _fail("caused_by", String(partner_id), String(need), "")


static func _aggregate(
	state: SocialState, requirement: Dictionary, verb: StringName, all_must: bool, invert: bool
) -> Dictionary:
	var parts: Array = requirement.get("requirements", [])
	if parts.is_empty():
		return _pass()
	var unmet: Array[Dictionary] = []
	for part in parts:
		var result := evaluate(state, part)
		if not result.get("ok", false):
			for entry in result.get("unmet", []):
				unmet.append(entry)
	# `none_of` is the odd one out: it opens only when every child is unmet.
	var ok := unmet.is_empty()
	if invert:
		ok = unmet.size() == parts.size()
	elif not all_must:
		ok = unmet.size() < parts.size()
	if ok:
		return _pass()
	return {"ok": false, "reason": String(verb), "unmet": unmet}


## Refuse because the gate could not be evaluated at all: there is no social
## state to read. Refuses closed and names itself, like an unknown verb, so a
## caller holding no ledger sees the reason instead of an unlocked gate.
static func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [{"kind": "state", "id": reason, "required": "a_social_state", "label": reason}],
	}


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: String, id: String, required: String, actual: String) -> Dictionary:
	return {
		"ok": false,
		"reason": kind,
		"unmet": [{"kind": kind, "id": id, "required": required, "actual": actual, "label": id}],
	}
