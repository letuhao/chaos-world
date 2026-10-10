class_name StoryGate
extends RefCounted

## Evaluates an authored story requirement against the state other modules own, and
## adds exactly ONE verb to the vocabulary `EventGate` / `DestinyGate` / `SocialGate`
## already share (ADR 0113: "a gate reading a fact is a new verb in one evaluator, not a
## new system").
##
## ## The verbs, and where each is READ
##
## A requirement is data, never code — either empty (ungated) or one `{verb, ...}` map:
##
##   `{verb: "quest_done", id: &"<quest_id>"}`  — the quest ledger, via `QuestApi`
##   `{verb: "fact",       id: &"<fact_id>", need: 3}` — the shared world fact ledger
##   `{verb: "has_fate",   id: &"<fate_id>"}`    — `DestinyApi`, delegated
##   `{verb: "has_destiny",id: &"<destiny_id>"}` — `DestinyApi`, delegated
##   `{verb: "counter",    id: &"<counter_id>", need: 3}` — `DestinyApi`, delegated
##   `{verb: "tagged",     id: &"<lineage_tag>"}` — `DestinyApi`, delegated
##   `{verb: "all_of",     of: [...]}`
##   `{verb: "any_of",     of: [...]}`
##   `{verb: "none_of",    of: [...]}`
##
## **Only `quest_done` is this module's own.** `fact` is delegated to `WorldFact`, the
## ledger's one read, and every fate verb goes to `DestinyApi.gate` verbatim, so there is
## exactly one fate evaluator in this repo and story cannot become a second one answering
## a slightly different question. `EventGate` is the precedent for all three moves.
##
## ## Why `quest_done` is needed at all, and why it is not a fact
##
## The clean answer would be "a completed quest already records a fact, so use `fact`".
## It does not: `QuestApi.complete` pays grants and stamps the quest ledger, and writes
## nothing to `WorldFact`. So either story re-implements a quest read, or the shared
## language gains a verb that reads the quest ledger the way `EventGate` gained one that
## reads the fact ledger. The second is what ADR 0113 prescribes and what this file does.
##
## **The asymmetry is worth naming.** A quest step reads the ledger, so a quest can be
## satisfied by anything the world remembers. A chapter reads the quest ledger, so a
## chapter can be finished by anything the player was handed. That is the difference
## between authored progression and emergent progression, and it is why a chapter gates
## on a quest while a systemic quest gates on a fact.
##
## ## Refuse-with-cause, never a silent false
##
## An unknown verb returns `reason: "unknown_verb"` and NAMES ITSELF, and a malformed row
## returns `malformed`. `StoryDef.problems()` walks the same vocabulary over the authored
## tree, so a typo in a `.tres` is caught by a tool rather than waiting for a player to
## fail to open the chapter it locked. A refusal is a content bug; an unmet is a player
## being told not yet. The two must never be confused, because a gate that returns
## `unmet` for its own typo makes broken content look like progression.

## The composite verbs, reused verbatim from the shared requirement language. Named
## individually rather than only as an array because a `match` pattern wants a constant,
## and `EventGate` already spells them this way.
const VERB_ALL_OF := &"all_of"
const VERB_ANY_OF := &"any_of"
const VERB_NONE_OF := &"none_of"
const COMPOSITE_VERBS: Array[StringName] = [VERB_ALL_OF, VERB_ANY_OF, VERB_NONE_OF]

## The one verb this module contributes: a quest is in the actor's COMPLETED set.
const VERB_QUEST_DONE := &"quest_done"

## The verb `EventGate` contributes and this module reads through the SAME ledger, so a
## chapter can gate on a world fact without a second fact reader.
const VERB_FACT := &"fact"

## The verbs `DestinyGate` owns and this module DELEGATES rather than re-implements.
## Listed so a content guard can tell a typo from a delegation.
const DELEGATED_VERBS: Array[StringName] = [&"has_fate", &"has_destiny", &"counter", &"tagged"]

## The full vocabulary this module reads: the two it contributes plus the four it
## delegates. A verb outside this set is a content bug and is named as one.
const KNOWN_VERBS: Array[StringName] = [
	VERB_QUEST_DONE,
	VERB_FACT,
	VERB_ALL_OF,
	VERB_ANY_OF,
	VERB_NONE_OF,
	&"has_fate",
	&"has_destiny",
	&"counter",
	&"tagged",
]


## `{ok: bool, reason: String, unmet: Array[Dictionary]}` — the shape `DestinyGate.evaluate`
## and `EventGate.evaluate` already produce, so a panel renders a reason it did not have
## to invent.
##
## `actor` is null-safe: a caller holding no ledger reads every gate as unmet rather than
## as an error, which is the same reading `DestinyState.empty()` gives.
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
		VERB_QUEST_DONE:
			return _quest_done(actor, requirement)
		VERB_FACT:
			return _fact(actor, requirement)
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


## Every verb appearing anywhere inside `requirement`, composites included. One walk so a
## content guard can find a typo nested three levels deep inside an `all_of`.
##
## Bounded by the authored nesting: a composite names exactly its own children, so the
## depth is what the author wrote and never an unbounded search.
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


## The actor's completed quest set, read through the quest FACADE. Naming
## `QuestCatalog` or `QuestState` from here would be a second, undeclared edge into a
## module story already depends on; `api.gd` is the only file another module may reach.
static func _quest_done(actor: Actor, requirement: Dictionary) -> Dictionary:
	var quest_id := StringName(requirement.get("id", ""))
	if quest_id == &"":
		return _refuse("malformed", "", "A quest_done requirement names no quest id.")
	if actor == null:
		return _fail("no_ledger", "", "a quest ledger", "none")
	var done: Array = QuestApi.summary(actor).get("completed", [])
	if done.has(String(quest_id)):
		return _pass()
	return {
		"ok": false,
		"reason": "unmet",
		"unmet":
		[
			{
				"kind": "quest",
				"id": String(quest_id),
				"required": true,
				"actual": false,
				"label": "Finish '%s' first." % String(quest_id),
			}
		],
	}


## The one fact read, delegated to the ledger's own reader rather than re-implemented.
## `actual` is read ONCE: the label and the row must report the same number, and two
## calls to a ledger that another system may be writing are two chances to disagree.
static func _fact(actor: Actor, requirement: Dictionary) -> Dictionary:
	var fact_id := StringName(requirement.get("id", ""))
	if fact_id == &"":
		return _refuse("malformed", "", "A fact requirement names no fact id.")
	var need := maxi(1, int(requirement.get("need", 1)))
	var actual := 0 if actor == null else WorldFact.count(actor, fact_id)
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


## Hand the requirement to the module that owns the verb, unchanged. Its verdict is
## returned as-is rather than re-shaped, so the composite below can tell a genuine
## "unmet" from the same module's "unknown_verb" refusal.
static func _delegate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if actor == null:
		return _fail("delegated", "", "a_ledger", "none")
	return DestinyApi.gate(actor, requirement)


## One composite verb over a list of child requirements. The three verbs differ in TWO
## ways, not one, which is why the arguments are named rather than positional:
## `require_all` selects the first two by counting how many passed, and `refuse_when_any`
## inverts that count for `none_of`. Passing `true` for `refuse_when_any` on `any_of`
## silently turns it into `none_of`.
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
		# nested requirement that cannot be read is never treated as satisfied. The
		# reason set is `DestinyGate`'s, not a second copy of it.
		var nested_reason := String(verdict.get("reason", ""))
		if DestinyGate.POISON_REASONS.has(nested_reason):
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


## A refusal is distinct from an unmet requirement: the requirement itself is unreadable,
## which is a content bug rather than a player being told no. It refuses closed and names
## the offending verb, the `DestinyGate` precedent.
static func _refuse(reason: String, id: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [{"kind": "gate", "id": id, "required": true, "actual": false, "label": label}],
	}
