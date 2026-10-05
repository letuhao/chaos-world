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
##   `{verb: &"tagged",       id: &"oath"}` — holds ANY fate carrying that tag
##   `{verb: &"all_of",       of: [ ...requirements ]}`
##   `{verb: &"any_of",       of: [ ...requirements ]}`
##   `{verb: &"none_of",      of: [ ...requirements ]}`
##
## A requirement with no verb, or a verb that is not one of the seven, refuses
## closed and names itself — and so does a composite whose `of` list holds
## anything that is not itself a requirement. Refuse-with-cause is the house
## rule: content that is malformed must fail loudly and locally, never open a
## door it cannot read.
##
## ## `tagged` refuses `unknown_tag`, and that is NOT an `unmet`
##
## The `id` of a `tagged` gate must be inside [constant FateDef.TAGS]. A tag
## outside the closed vocabulary refuses with `reason: "unknown_tag"` and names
## itself, exactly as an unknown verb does — because an unknown tag is a content
## bug (a coined lineage nothing carries), and degrading it to a plain `unmet`
## would report it forever as though a player could go and earn it (ADR 0196, fate tag vocabulary).
##
## **One alias rule, every place a destiny is asked about.** `holds_destiny()`
## below is the single resolver, and EVERY read of the question routes through it:
## the `has_destiny` verb, `earnable()`, and `unmet_prerequisites()`. This is not
## tidiness — it is the only way an authored id and its declaring destiny can be
## one answer rather than two, because the moment one call site reads the raw
## ledger key instead, that call site stops believing in `gate_aliases` and the
## feature silently stops existing for exactly the author it was written for.
## `DestinyApi.has_destiny` asks this same method rather than keeping a copy.

## ## The reasons that POISON a composite rather than failing as one child
##
## A leaf that refuses closed because the requirement could not be READ is not a
## player being told no, and it must not be counted as one: it is returned
## verbatim so the parent carries the cause instead of accumulating it into an
## `unmet` list that reads as though the player could go and earn the answer.
##
## **`unknown_tag` is a member and that is the half that is easy to miss.** A
## `tagged` leaf naming a coined lineage was correct to refuse; dropping it from
## this list degrades it to a plain `unmet` the instant it is nested, so
## `all_of:[{tagged:"oath"},{tagged:"not_a_tag"}]` reports "you need an oath fate"
## — an actionable, false cause — instead of the content bug it is (ADR 0196, fate tag vocabulary).
const POISON_REASONS: Array[String] = ["malformed", "unknown_verb", "unknown_tag"]


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
		&"tagged":
			return _tagged(actor, requirement)
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
##
## **`requires_destinies` is read through [method holds_destiny], not through
## [method DestinyState.has_destiny].** The two are different questions, and only
## one of them is the one a prerequisite means. `has_destiny` is a raw key lookup:
## it answers "is this exact string a key", which is the right question for a ledger
## write and the wrong one for an authored requirement. A prerequisite is a NAMESAKED
## thing story may name, and [member DestinyDef.gate_aliases] exists precisely so
## story can name a destiny before it exists — so the alias is the case this
## requirement was written for, and reading it raw made it the one kind of
## prerequisite that could never be satisfied.
static func earnable(ledger: Dictionary, def: DestinyDef) -> bool:
	if def == null:
		return false
	for destiny_id in def.requires_destinies:
		if not holds_destiny(ledger, destiny_id):
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
##
## **`requires_destinies` is asked through [method holds_destiny] here for the same
## reason [method earnable] asks it there**: an alias and the destiny that declares
## it are one answer, so this list and `earnable()` can never disagree about whether
## a prerequisite is outstanding. A panel reading this to explain a locked destiny
## used to report an alias permanently unmet while `earnable()` — once it was fixed —
## opened the gate, and the two statements would have been flatly contradictory.
##
## The `id` reported is the one AUTHOR WROTE, not the resolved definition: the entry
## is rendered back to whoever wrote the requirement, and echoing
## `the_one_who_returned` at an author who typed `the_returned` names a destiny they
## never mentioned and does not tell them what to go and earn.
static func unmet_prerequisites(ledger: Dictionary, def: DestinyDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for destiny_id in def.requires_destinies:
		if not holds_destiny(ledger, destiny_id):
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


## ## `tagged` — the lineage verb. OR across fates, over a CLOSED vocabulary.
##
## Satisfied by holding **any one** fate that carries `tag_id`. Tags are unordered
## and have no primary, so there is no defensible per-fate reading: a gate that
## wanted a specific fate writes `has_fate`, which already says exactly that. The
## one question this verb adds is "does this actor carry any fate OF THIS KIND",
## and the answer is a disjunction over the ledger.
##
## Three refusals, kept apart on purpose (ADR 0196, fate tag vocabulary):
##   no `id`           -> `malformed`. It NEVER defaults to "any tagged fate
##                        satisfies this", which would make a half-written gate
##                        silently open for anyone holding one tagged fate.
##   `id` outside
##   [constant FateDef.TAGS] -> `unknown_tag`, naming the tag. NEVER `unmet`:
##                        nothing in the tree carries a coined tag, so `unmet`
##                        would be a permanent lie with no cause an author could
##                        act on.
##   in vocabulary,
##   carried by nobody held -> `unmet`, and the entry names THE TAG THE AUTHOR
##                        WROTE, never a resolved fate id — the same rule
##                        [method unmet_prerequisites] states for aliases.
##
## It only READS the ledger. `DestinyState.has_fate` is a lookup, and a tag is
## consulted rather than consumed, so a `tagged` gate can never remove a fate
## (ADR 0065 earn-only).
static func _tagged(actor: Actor, requirement: Dictionary) -> Dictionary:
	var tag_id := StringName(requirement.get("id", ""))
	if tag_id == &"":
		return _refuse("malformed", requirement, "A tagged gate names no tag id.")
	if not FateDef.TAGS.has(tag_id):
		return _refuse(
			"unknown_tag",
			requirement,
			(
				"Gate tag '%s' is not one of the lineage vocabulary (ADR 0196, fate tag vocabulary)."
				% tag_id
			)
		)
	var ledger := _ledger(actor)
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		# A `null` definition is not a match and not a crash: the catalog answers
		# `null` for an id it does not hold, and a gate must not be the thing that
		# turns that into an abort.
		if def == null or not def.tags.has(tag_id):
			continue
		if DestinyState.has_fate(ledger, fate_id):
			return _pass()
	return _fail(&"tag", tag_id, true, false, "Requires a fate marked '%s'" % tag_id)


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
		# An unreadable child poisons the whole composite; see [constant POISON_REASONS].
		var nested_reason := String(verdict.get("reason", ""))
		if POISON_REASONS.has(nested_reason):
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
