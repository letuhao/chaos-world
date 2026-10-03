class_name EventGate
extends RefCounted

## Evaluates an authored event requirement against the two ledgers an event may
## read, and adds exactly ONE verb to the vocabulary `DestinyGate` / `SocialGate`
## already own (ADR 0113: "a gate reading a fact is a new verb in one evaluator, not
## a new system").
##
## ## The verbs, and where each is READ
##
## A requirement is data, never code — either empty (ungated, always open) or one
## `{verb, ...}` map:
##
##   `{verb: "fact",       id: &"<fact_id>", need: 3}`  — the world fact ledger
##   `{verb: "declare",    other_id: &"<polity>"}`      — the war's sides and prize
##   `{verb: "has_fate",   id: &"<fate_id>"}`           — DestinyApi, delegated
##   `{verb: "counter",    id: &"<counter_id>", need: 3}` — DestinyApi, delegated
##   `{verb: "all_of",     of: [...]}`
##   `{verb: "any_of",     of: [...]}`
##   `{verb: "none_of",    of: [...]}`
##
## **Only `fact` and `declare` are local.** Every other verb is handed to
## `DestinyApi.gate` verbatim, so there is exactly one fate evaluator in this repo
## and this module cannot become a second one that answers a slightly different
## question.
##
## ## `declare` is a verb that gates NOTHING about the player
##
## A `sect_war` authors its declaration inside its own trigger:
## `{verb: "declare", other_id, territory_id, mode, transfer, standing}`. It is not a
## requirement — there is no ledger question it asks, and a world where the war is
## "levied" is the same world in every period. It is a PAYLOAD the director reads
## ([method EventApi._war_declaration]) and hands to `NationApi.declare_war`.
##
## It is nonetheless a verb in the requirement language, so it must be one this
## evaluator can read: a requirement naming a verb the gate does not know refuses
## closed, which made every authored `sect_war` unopenable with
## `trigger_unmet/unknown_verb` — a war that exists in content and in a test and
## cannot happen in the game. It passes when it names an `other_id` and refuses
## `malformed` when it does not, because a war whose sides cannot be read must not
## open with no declared prize (ADR 0085).
##
## ## Refuse-with-cause, never a silent false
##
## An unknown verb returns `reason: "unknown_verb"` and NAMES ITSELF. `catalog_report`
## walks the same walk over the authored tree, so a typo in a `.tres` is caught by
## a tool rather than waiting for a player to fail to open the event it locked.

## The composite verbs, reused verbatim from the shared requirement language.
const VERB_ALL_OF := &"all_of"
const VERB_ANY_OF := &"any_of"
const VERB_NONE_OF := &"none_of"
const COMPOSITE_VERBS: Array[StringName] = [VERB_ALL_OF, VERB_ANY_OF, VERB_NONE_OF]

## The verb a `sect_war` authors its sides and prize under. A payload rather than a
## requirement — see the class docstring — but a requirement-language verb all the
## same, so it is read here instead of being reported as a typo in every `.tres`.
const VERB_DECLARE := &"declare"

## The verbs `DestinyGate` owns and this module therefore DELEGATES rather than
## re-implements. Listed so `catalog_report` can tell a typo from a delegation.
const DELEGATED_VERBS: Array[StringName] = [&"has_fate", &"has_destiny", &"counter"]

## The full vocabulary this module reads: the two it contributes plus the three it
## delegates. A verb outside this set is a content bug and is named as one.
const KNOWN_VERBS: Array[StringName] = [
	EventFacts.VERB_FACT,
	VERB_DECLARE,
	VERB_ALL_OF,
	VERB_ANY_OF,
	VERB_NONE_OF,
	&"has_fate",
	&"has_destiny",
	&"counter",
]


## `{ok: bool, reason: String, unmet: Array[Dictionary]}` — the same shape
## `DestinyGate.evaluate` and `ItemRequirement.unmet()` already produce, so a panel
## renders a reason it did not have to invent.
##
## `actor` is null-safe: a caller holding no ledger reads every gate as unmet rather
## than as an error, which is the same reading `DestinyState.empty()` gives.
static func evaluate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty():
		return _pass()
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse(
			"malformed",
			"",
			"A requirement names no verb. An EMPTY requirement is ungated; this one is not empty."
		)
	match verb:
		EventFacts.VERB_FACT:
			return _has_fact(actor, requirement)
		VERB_DECLARE:
			return _declaration(requirement)
		VERB_ALL_OF:
			return _composite(actor, requirement, true, false)
		VERB_ANY_OF:
			return _composite(actor, requirement, false, false)
		VERB_NONE_OF:
			return _composite(actor, requirement, false, true)
		_:
			if DELEGATED_VERBS.has(verb):
				return _delegate(actor, requirement)
			return _refuse(
				"unknown_verb", String(verb), "Gate verb '%s' is not one this module reads." % verb
			)


## Every verb appearing anywhere inside `requirement`, composites included. One walk
## so `catalog_report` can find a typo nested three levels deep inside an `all_of`.
static func verbs_in(requirement: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if requirement.is_empty():
		return out
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		out.append(verb)
		return out
	out.append(verb)
	if not COMPOSITE_VERBS.has(verb):
		return out
	var children = requirement.get("of", [])
	if not (children is Array):
		return out
	for child in children as Array:
		if not (child is Dictionary):
			continue
		for nested in verbs_in(child as Dictionary):
			if not out.has(nested):
				out.append(nested)
	return out


# --- Internals -------------------------------------------------------------


static func _has_fact(actor: Actor, requirement: Dictionary) -> Dictionary:
	var fact_id := StringName(requirement.get("id", ""))
	if fact_id == &"":
		return _refuse("malformed", "", "A fact requirement names no fact id.")
	var need := maxi(1, int(requirement.get("need", 1)))
	var ledger := EventFacts.ledger(actor)
	var actual := EventFacts.count_of(ledger, fact_id)
	if actual >= need:
		return _pass()
	return {
		"ok": false,
		"reason": "unmet",
		"unmet":
		[
			{
				"kind": "fact",
				"id": String(fact_id),
				"required": need,
				"actual": actual,
				"label": "'%s' %d of %d" % [fact_id, actual, need],
			}
		],
	}


## A `declare` row reads as READABLE or it refuses — and it is the only question
## asked of it. `actor` is deliberately NOT a parameter: this verb gates nothing
## about the player, so the verdict cannot depend on a ledger and the composite
## above may mix it freely with `fact` rows.
##
## Refusing on an unreadable declaration is the refusal that matters. A `sect_war`
## whose `declare` row names no `other_id` would otherwise pass its own trigger,
## open, and then be refused by `EventApi._declare` after `begin` had already
## written the active row — a war that exists for one call and names no sides.
static func _declaration(requirement: Dictionary) -> Dictionary:
	if String(requirement.get("other_id", "")) == "":
		return _refuse(
			"malformed", "", "A declare row names the war's other side. This one names no other_id."
		)
	return _pass()


## Hand the requirement to the module that owns the verb, unchanged. Its verdict is
## returned as-is rather than re-shaped, so the composite above can tell a genuine
## "unmet" from the same module's "unknown_verb" refusal.
static func _delegate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if actor == null:
		return _fail("delegated", "", "a_ledger", "none")
	return DestinyApi.gate(actor, requirement)


## One composite verb over a list of child requirements. The three verbs differ in
## TWO ways, not one — that is why the arguments are named rather than passed
## positionally: `require_all` selects the first two by counting how many passed,
## and `refuse_when_any` inverts that count for `none_of`. Passing `true` for
## `refuse_when_any` on `any_of` silently inverts it into `none_of`.
static func _composite(
	actor: Actor, requirement: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", "", "A composite requirement names no children.")
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		if not (child is Dictionary):
			return _refuse(
				"malformed", "", "A composite requirement holds a child that is not a requirement."
			)
		var verdict := evaluate(actor, child as Dictionary)
		if bool(verdict.get("ok", false)):
			passed += 1
			continue
		# A malformed child poisons the whole composite: refuse-with-cause means a
		# nested requirement that cannot be read is never treated as satisfied.
		var nested_reason := String(verdict.get("reason", ""))
		if nested_reason == "malformed" or nested_reason == "unknown_verb":
			return verdict
		for entry in verdict.get("unmet", []) as Array:
			if entry is Dictionary:
				unmet.append(entry as Dictionary)
	var total := (children as Array).size()
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: String, id: String, required, actual) -> Dictionary:
	return {
		"ok": false,
		"reason": kind,
		"unmet":
		[
			{
				"kind": kind,
				"id": id,
				"required": required,
				"actual": actual,
				"label": "Requires a ledger this actor does not carry.",
			}
		],
	}


## A refusal is distinct from an unmet requirement: the requirement itself is
## unreadable, which is a content bug rather than a player being told no. It
## refuses closed and names the offending verb, the `DestinyGate` precedent.
static func _refuse(reason: String, id: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [{"kind": "gate", "id": id, "required": true, "actual": false, "label": label}],
	}
