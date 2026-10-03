class_name DestinyGate
extends RefCounted

## Evaluates authored gate requirements against an actor, and decides whether a
## destiny may be earned at all.
##
## A requirement is **data, never code**: either an empty dictionary — ungated,
## always open — or a map naming exactly one verb. No GDScript is authored per
## gate, so adding story content is a content edit, not a code change.
##
## Verbs (a closed set — an unknown verb is refused, never silently true):
##   `{verb: &"has_fate",     id: &"oath_breaker"}`
##   `{verb: &"has_destiny",  id: &"chosen_one"}`   — an alias also answers true
##   `{verb: &"counter",      id: &"duels_won", need: 3}`
##   `{verb: &"all_of",       of: [ ...requirements ]}`
##   `{verb: &"any_of",       of: [ ...requirements ]}`
##   `{verb: &"none_of",      of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of the six, refuses
## closed and names itself — and so does a composite whose `of` list holds
## anything that is not itself a requirement. Refuse-with-cause is the house
## rule: content that is malformed must fail loudly and locally, never open a
## door it cannot read.


## The full verdict, always this shape:
## `{ok: bool, reason: String, unmet: Array[Dictionary]}` where every unmet entry
## is `{kind, id, required, actual, label}` — the shape `ItemRequirement.unmet()`
## already produces, so a panel renders a reason it did not have to invent.
static func evaluate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty():
		return _pass()
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse("malformed", requirement, "A gate names no verb.")
	match verb:
		&"has_fate":
			return _has_fate(actor, requirement)
		&"has_destiny":
			return _has_destiny(actor, requirement)
		&"counter":
			return _counter(actor, requirement)
		&"all_of":
			return _composite(actor, requirement, true, false)
		&"any_of":
			return _composite(actor, requirement, false, false)
		&"none_of":
			return _composite(actor, requirement, false, true)
		_:
			return _refuse(
				"unknown_verb", requirement, "Gate verb '%s' is not one this module reads." % verb
			)


## Whether `def` may be earned by `actor` right now: every prerequisite is held,
## and no other destiny in its exclusivity group is held.
##
## Used by `DestinyApi.earn_destiny`, so the rule lives in exactly one place and
## the facade does not re-implement it.
static func earnable(ledger: Dictionary, def: DestinyDef) -> bool:
	if def == null:
		return false
	for destiny_id in def.requires_destinies:
		if not DestinyState.has_destiny(ledger, destiny_id):
			return false
	for fate_id in def.requires_fates:
		if not DestinyState.has_fate(ledger, fate_id):
			return false
	if def.group == &"":
		return true
	for other_id in FateCatalog.instance().destinies_in_group(def.group):
		if other_id != def.id and DestinyState.has_destiny(ledger, other_id):
			return false
	return true


## Every prerequisite `def` names that the actor does not yet hold, as
## `{kind, id, required, actual, label}` entries. Empty means earnable, so a UI
## can show why a destiny has not arrived without re-deriving the rule.
static func unmet_prerequisites(ledger: Dictionary, def: DestinyDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for destiny_id in def.requires_destinies:
		if not DestinyState.has_destiny(ledger, destiny_id):
			(
				out
				. append(
					{
						"kind": &"destiny",
						"id": String(destiny_id),
						"required": true,
						"actual": false,
						"label": "Requires the destiny '%s'" % destiny_id,
					}
				)
			)
	for fate_id in def.requires_fates:
		if not DestinyState.has_fate(ledger, fate_id):
			(
				out
				. append(
					{
						"kind": &"fate",
						"id": String(fate_id),
						"required": true,
						"actual": false,
						"label": "Requires the fate '%s'" % fate_id,
					}
				)
			)
	if def.group != &"":
		for other_id in FateCatalog.instance().destinies_in_group(def.group):
			if other_id == def.id or not DestinyState.has_destiny(ledger, other_id):
				continue
			(
				out
				. append(
					{
						"kind": &"exclusive",
						"id": String(other_id),
						"required": false,
						"actual": true,
						"label": "Closed by the destiny '%s'" % other_id,
					}
				)
			)
	return out


# --- Internals -------------------------------------------------------------


static func _has_fate(actor: Actor, requirement: Dictionary) -> Dictionary:
	var fate_id := StringName(requirement.get("id", ""))
	if fate_id == &"":
		return _refuse("malformed", requirement, "A has_fate gate names no fate id.")
	var held := DestinyState.has_fate(_ledger(actor), fate_id)
	if held:
		return _pass()
	return _fail(&"fate", fate_id, true, false, "Requires the fate '%s'" % fate_id)


static func _has_destiny(actor: Actor, requirement: Dictionary) -> Dictionary:
	var destiny_id := StringName(requirement.get("id", ""))
	if destiny_id == &"":
		return _refuse("malformed", requirement, "A has_destiny gate names no destiny id.")
	var held := holds_destiny(_ledger(actor), destiny_id)
	if held:
		return _pass()
	return _fail(&"destiny", destiny_id, true, false, "Requires the destiny '%s'" % destiny_id)


static func _counter(actor: Actor, requirement: Dictionary) -> Dictionary:
	var counter_id := StringName(requirement.get("id", ""))
	if counter_id == &"":
		return _refuse("malformed", requirement, "A counter gate names no counter id.")
	var need := int(requirement.get("need", 1))
	if need < 1:
		return _refuse("malformed", requirement, "A counter gate needs a positive `need`.")
	var total := DestinyState.counter_value(_ledger(actor), counter_id)
	if total >= need:
		return _pass()
	return _fail(&"counter", counter_id, need, total, "'%s' %d of %d" % [counter_id, total, need])


## One composite verb over a list of child requirements.
##
## The three verbs are distinct in TWO ways, not one, which is the whole reason
## the arguments are named rather than passed positionally:
##   all_of  — every child must hold
##   any_of  — at least one child must hold
##   none_of — no child may hold
## `require_all` selects the first two by counting how many passed, and
## `refuse_when_any` inverts that count for `none_of`. Passing `true` for
## `refuse_when_any` on `any_of` silently inverts it into `none_of`, so the pair
## is asserted at the dispatch site rather than trusted to the caller.
static func _composite(
	actor: Actor, requirement: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", requirement, "A composite gate names no children.")
	# Every ELEMENT is checked, because `children` is only known to be an Array.
	# A bare string child used to reach `evaluate(actor, child as Dictionary)`,
	# and that cast is not a refusal — it is a NULL one. `evaluate()` then took
	# `null.is_empty()` on it, which is a hard engine error, not the documented
	# `{ok:false, reason:"malformed"}` verdict: a crash where the module promises
	# a cause. Refused here instead, loudly and locally, naming the parent.
	#
	# Deliberately NOT `children as Array[Dictionary]`: that conversion yields an
	# EMPTY array when any element fails it, so one bad child would silently
	# reduce `all_of` to no children at all — and `all_of` over nothing is true.
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		if not (child is Dictionary):
			return _refuse(
				"malformed",
				requirement,
				"A composite gate holds a child that is not a requirement."
			)
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
	return {
		"ok": false,
		"reason": "unmet",
		"unmet": unmet,
	}


## Whether `ledger` records `destiny_id` **or an alias authored for it**.
##
## One place, BOTH directions, because an alias is only a name for the destiny it
## was declared on and the two are the same answer whichever one is asked for:
##
##   forward  — `the_one_who_returned` declares `the_returned`, and holding
##              either answers for the other. This is what `FateCatalog
##              .destiny_gate_ids()` lists.
##   reverse  — `the_returned` is a pure narrative id: no `the_returned.tres`
##              ships, because the whole point of declaring it is that story can
##              be authored before the destiny it will answer for exists. So an
##              id that is not itself a destiny is resolved by scanning the
##              authored `gate_aliases` for it. Without this, every gate authored
##              against an alias of an unearned-or-absent definition reads false,
##              and the alias costs a content author nothing for that.
##
## The catalog is cached, so the reverse scan is a walk of the destiny
## definitions, not of the content tree.
##
## Refuses to widen: only an id that some definition DECLARES as its alias
## resolves, never an id that merely looks like one, and never an alias claimed
## by two destinies — a contested alias resolves to nothing rather than to
## whichever definition the scan reached first.
static func holds_destiny(ledger: Dictionary, destiny_id: StringName) -> bool:
	if DestinyState.has_destiny(ledger, destiny_id):
		return true
	var def := FateCatalog.instance().destiny_definition(destiny_id)
	if def != null:
		for alias in def.gate_aliases:
			if DestinyState.has_destiny(ledger, alias):
				return true
		return false
	return DestinyState.has_destiny(ledger, _alias_target(destiny_id))


## The destiny `id` was declared as an alias of, or `&""` when no definition
## declares it — or when two do. One, not a list, because a list would let an
## alias satisfy both exclusive branches of the same group, which is the one
## answer an alias must never be able to give.
static func _alias_target(id: StringName) -> StringName:
	var found: Array[StringName] = []
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def != null and def.gate_aliases.has(id):
			found.append(destiny_id)
	if found.size() == 1:
		return found[0]
	return &""


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return DestinyState.empty()
	return DestinyState.normalize(actor.get_module_data(DestinyState.MODULE_KEY))


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


## A refusal is distinct from a normal failure: the requirement itself is
## unreadable, which is a content bug rather than a player being told no.
static func _refuse(reason: String, _requirement: Dictionary, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [{"kind": "gate", "id": "", "required": true, "actual": false, "label": label}],
	}
